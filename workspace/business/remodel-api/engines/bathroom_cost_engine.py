"""
Bathroom Cost Engine - Deterministic rule-based cost calculator
"""
from typing import List, Dict, Any
from uuid import UUID
import asyncpg

from app.models import (
    BathroomAnswers,
    CostRule,
    RuleMatchResult,
    ModuleResult,
    EstimateResult,
    CostSummary,
    CostModule,
    ProjectSummary,
    EducationalContent,
    AnalysisContent
)


class BathroomCostEngine:
    """
    Deterministic cost calculation engine for bathroom remodels.

    Process:
    1. Load all active rules for 'bathroom' engine
    2. Match rules against user answers using applies_when conditions
    3. Calculate costs per rule (base + per_sqft)
    4. Aggregate by module
    5. Calculate labor/material split
    6. Compute complexity score
    7. Generate educational content
    """

    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def calculate(
        self,
        project_id: UUID,
        answers: BathroomAnswers
    ) -> EstimateResult:
        """
        Main entry point: calculate cost estimate for a project.

        Args:
            project_id: UUID of the project
            answers: Complete set of user answers

        Returns:
            EstimateResult with costs, modules, and education
        """
        # Step 1: Load all active rules for bathroom engine
        rules = await self._load_rules()

        # Step 2: Match rules and calculate costs
        module_results = await self._calculate_modules(answers, rules)

        # Step 3: Aggregate totals
        cost_summary = self._aggregate_costs(module_results)

        # Step 4: Calculate complexity
        complexity_score = self._calculate_complexity(module_results, answers)
        complexity_band = self._complexity_band(complexity_score)

        # Step 5: Generate scope text
        scope_text = self._generate_scope_text(answers)

        # Step 6: Identify cost drivers
        cost_drivers = self._identify_cost_drivers(module_results, answers)

        # Step 7: Build response
        return EstimateResult(
            project_id=project_id,
            summary=ProjectSummary(
                scope_text=scope_text,
                complexity_band=complexity_band,
                complexity_score=complexity_score
            ),
            cost=cost_summary,
            modules=[
                CostModule(
                    module_key=m.module_key,
                    label=m.label,
                    total_min=m.total_min,
                    total_max=m.total_max,
                    labor_min=m.labor_min,
                    labor_max=m.labor_max,
                    materials_min=m.materials_min,
                    materials_max=m.materials_max
                )
                for m in module_results
            ],
            education=EducationalContent(
                cost_drivers=cost_drivers,
                questions_for_contractors=self._get_contractor_questions()
            ),
            analysis=AnalysisContent()  # Stubbed for now
        )

    async def _load_rules(self) -> List[CostRule]:
        """Load all active cost rules for bathroom engine"""
        query = """
            SELECT
                id, engine, module_key, rule_key, applies_when,
                base_cost_min, base_cost_max,
                cost_per_sqft_min, cost_per_sqft_max,
                labor_fraction, complexity_points, notes, active
            FROM cost_rules
            WHERE engine = 'bathroom' AND active = true
            ORDER BY module_key, rule_key
        """

        rows = await self.conn.fetch(query)

        return [
            CostRule(
                id=row['id'],
                engine=row['engine'],
                module_key=row['module_key'],
                rule_key=row['rule_key'],
                applies_when=row['applies_when'],
                base_cost_min=float(row['base_cost_min']),
                base_cost_max=float(row['base_cost_max']),
                cost_per_sqft_min=float(row['cost_per_sqft_min']),
                cost_per_sqft_max=float(row['cost_per_sqft_max']),
                labor_fraction=float(row['labor_fraction']),
                complexity_points=row['complexity_points'],
                notes=row['notes'],
                active=row['active']
            )
            for row in rows
        ]

    def _rule_matches(self, rule: CostRule, answers: BathroomAnswers) -> bool:
        """
        Check if a rule's applies_when condition matches the answers.

        Supported conditions:
        - {"goals_contains": "convert_tub_to_shower"}
        - {"tile_level": "porcelain"}
        - {"extras_contains": "heated_floor"}
        - Combinations with AND logic (all conditions must match)

        Args:
            rule: The cost rule to check
            answers: User's answers

        Returns:
            True if rule applies, False otherwise
        """
        applies_when = rule.applies_when

        # Empty condition = always applies
        if not applies_when:
            return True

        # Convert answers to dict for easier access
        answers_dict = answers.model_dump()

        # Check each condition
        for key, value in applies_when.items():
            # Special handling for "_contains" conditions
            if key.endswith("_contains"):
                field_name = key.replace("_contains", "")

                # Handle both "goals_contains" and "extras_contains"
                if field_name in answers_dict:
                    field_value = answers_dict[field_name]

                    # Field should be a list
                    if not isinstance(field_value, list):
                        return False

                    # Check if value is in the list
                    if value not in field_value:
                        return False
                else:
                    return False

            # Direct field match
            elif key in answers_dict:
                if answers_dict[key] != value:
                    return False
            else:
                # Field doesn't exist in answers
                return False

        # All conditions matched
        return True

    async def _calculate_modules(
        self,
        answers: BathroomAnswers,
        rules: List[CostRule]
    ) -> List[ModuleResult]:
        """
        Calculate costs for each module by matching rules.

        Returns:
            List of ModuleResult objects grouped by module_key
        """
        # Group rules by module_key
        modules_dict: Dict[str, List[CostRule]] = {}
        for rule in rules:
            if rule.module_key not in modules_dict:
                modules_dict[rule.module_key] = []
            modules_dict[rule.module_key].append(rule)

        # Calculate costs per module
        module_results = []

        for module_key, module_rules in modules_dict.items():
            # Match rules and calculate costs
            rule_matches = []
            total_min = 0.0
            total_max = 0.0
            labor_min = 0.0
            labor_max = 0.0
            materials_min = 0.0
            materials_max = 0.0
            complexity_points = 0

            for rule in module_rules:
                if self._rule_matches(rule, answers):
                    # Calculate cost for this rule
                    cost_min, cost_max = self._calculate_rule_cost(rule, answers)

                    # Split into labor and materials
                    rule_labor_min = cost_min * rule.labor_fraction
                    rule_labor_max = cost_max * rule.labor_fraction
                    rule_materials_min = cost_min * (1 - rule.labor_fraction)
                    rule_materials_max = cost_max * (1 - rule.labor_fraction)

                    # Accumulate
                    total_min += cost_min
                    total_max += cost_max
                    labor_min += rule_labor_min
                    labor_max += rule_labor_max
                    materials_min += rule_materials_min
                    materials_max += rule_materials_max
                    complexity_points += rule.complexity_points

                    # Track match
                    rule_matches.append(RuleMatchResult(
                        rule=rule,
                        matched=True,
                        labor_min=rule_labor_min,
                        labor_max=rule_labor_max,
                        materials_min=rule_materials_min,
                        materials_max=rule_materials_max,
                        total_min=cost_min,
                        total_max=cost_max
                    ))

            # Only include modules with matched rules
            if rule_matches:
                module_results.append(ModuleResult(
                    module_key=module_key,
                    label=self._module_label(module_key),
                    rules_matched=rule_matches,
                    total_min=total_min,
                    total_max=total_max,
                    labor_min=labor_min,
                    labor_max=labor_max,
                    materials_min=materials_min,
                    materials_max=materials_max,
                    complexity_points=complexity_points
                ))

        return module_results

    def _calculate_rule_cost(
        self,
        rule: CostRule,
        answers: BathroomAnswers
    ) -> tuple[float, float]:
        """
        Calculate cost contribution of a single rule.

        Returns:
            (cost_min, cost_max) tuple
        """
        # Start with base cost
        cost_min = rule.base_cost_min
        cost_max = rule.base_cost_max

        # Add per-sqft cost if applicable
        if rule.cost_per_sqft_min > 0 or rule.cost_per_sqft_max > 0:
            # Estimate sqft from size_sqft_band
            sqft = self._estimate_sqft(answers.size_sqft_band)

            # For shower walls, estimate ~90 sqft for standard shower
            # (This is a simplification; in production you'd want more detail)
            if rule.module_key == "tub_to_shower":
                sqft = 90  # Standard shower wall area

            cost_min += rule.cost_per_sqft_min * sqft
            cost_max += rule.cost_per_sqft_max * sqft

        return (cost_min, cost_max)

    def _estimate_sqft(self, size_band: str) -> float:
        """Convert size_sqft_band to estimated square footage"""
        mapping = {
            "0_35": 30,
            "35_60": 50,
            "60_90": 75,
            "90_plus": 100
        }
        return mapping.get(size_band, 50)

    def _aggregate_costs(self, modules: List[ModuleResult]) -> CostSummary:
        """Aggregate all module costs into a total summary"""
        total_min = sum(m.total_min for m in modules)
        total_max = sum(m.total_max for m in modules)
        labor_min = sum(m.labor_min for m in modules)
        labor_max = sum(m.labor_max for m in modules)
        materials_min = sum(m.materials_min for m in modules)
        materials_max = sum(m.materials_max for m in modules)

        return CostSummary(
            total_min=round(total_min, 2),
            total_max=round(total_max, 2),
            labor_min=round(labor_min, 2),
            labor_max=round(labor_max, 2),
            materials_min=round(materials_min, 2),
            materials_max=round(materials_max, 2)
        )

    def _calculate_complexity(
        self,
        modules: List[ModuleResult],
        answers: BathroomAnswers
    ) -> int:
        """
        Calculate complexity score based on modules and answers.

        Complexity drivers:
        - Structural layout changes: +3
        - Plumbing moves: +1-3
        - Custom tile shower: +2
        - Natural stone: +2
        - Each extra feature: +1
        """
        score = sum(m.complexity_points for m in modules)

        # Additional complexity from answers
        if answers.layout_change_level == "structural_changes":
            score += 3
        elif answers.layout_change_level == "non_structural_changes":
            score += 1

        if answers.plumbing_changes == "multiple_fixtures_moved":
            score += 3
        elif answers.plumbing_changes == "moving_toilet":
            score += 2
        elif answers.plumbing_changes == "moving_shower_or_tub":
            score += 1

        return score

    def _complexity_band(self, score: int) -> str:
        """Map complexity score to band"""
        if score <= 3:
            return "low"
        elif score <= 7:
            return "medium"
        else:
            return "high"

    def _module_label(self, module_key: str) -> str:
        """Convert module_key to human-readable label"""
        labels = {
            "tub_to_shower": "Tub to Shower Conversion",
            "wall_tile_replacement": "Wall Tile Replacement",
            "floor_tile_replacement": "Floor Tile Replacement",
            "vanity_replacement": "Vanity & Countertop",
            "plumbing_moves": "Plumbing Relocation",
            "layout_changes": "Layout Changes",
            "electrical_work": "Electrical Upgrades",
            "ventilation": "Ventilation",
            "extras": "Additional Features"
        }
        return labels.get(module_key, module_key.replace("_", " ").title())

    def _generate_scope_text(self, answers: BathroomAnswers) -> str:
        """Generate plain-English scope description"""
        parts = []

        # Main goals
        goals_text = {
            "convert_tub_to_shower": "converting the tub to a shower",
            "replace_wall_tile": "replacing wall tile",
            "replace_flooring": "replacing the flooring",
            "update_fixtures": "updating fixtures",
            "change_fixture_layout": "changing the fixture layout",
            "add_storage": "adding storage"
        }

        goal_descriptions = [
            goals_text[g] for g in answers.goals if g in goals_text
        ]

        if goal_descriptions:
            parts.append(f"You are planning a {answers.bathroom_type} bathroom remodel with {', '.join(goal_descriptions)}")

        # Layout changes
        if answers.layout_change_level == "structural_changes":
            parts.append("This involves structural changes to the layout")
        elif answers.layout_change_level == "non_structural_changes":
            parts.append("You're making minor layout adjustments")

        # Finishes
        if answers.tile_level:
            tile_desc = {
                "basic_ceramic": "basic ceramic tile",
                "porcelain": "porcelain tile",
                "natural_stone": "natural stone tile"
            }
            parts.append(f"using {tile_desc.get(answers.tile_level, 'tile')}")

        return ". ".join(parts) + "."

    def _identify_cost_drivers(
        self,
        modules: List[ModuleResult],
        answers: BathroomAnswers
    ) -> List[str]:
        """Identify the main cost drivers for this project"""
        drivers = []

        # Top expensive modules
        sorted_modules = sorted(modules, key=lambda m: m.total_max, reverse=True)
        for module in sorted_modules[:3]:  # Top 3
            drivers.append(
                f"{module.label}: ${int(module.total_min):,}-${int(module.total_max):,}"
            )

        # Specific expensive choices
        if answers.tile_level == "natural_stone":
            drivers.append("Natural stone tile adds significant material and labor costs")

        if "frameless_glass" in answers.extras:
            drivers.append("Frameless glass shower doors are custom-fabricated")

        if "heated_floor" in answers.extras:
            drivers.append("Heated floor systems require electrical work and specialized installation")

        if answers.plumbing_changes in ["moving_toilet", "multiple_fixtures_moved"]:
            drivers.append("Plumbing relocation is labor-intensive and requires permits")

        return drivers

    def _get_contractor_questions(self) -> List[str]:
        """Return standard questions clients should ask contractors"""
        return [
            "Are you licensed and insured for bathroom remodels?",
            "Can you provide references from recent similar projects?",
            "What's your estimated timeline for this scope of work?",
            "How do you handle change orders and unexpected issues?",
            "What warranties do you offer on labor and materials?",
            "Will you pull all necessary permits?",
            "What's your payment schedule?"
        ]
