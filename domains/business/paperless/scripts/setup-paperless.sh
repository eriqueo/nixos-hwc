#!/usr/bin/env bash
#
# setup-paperless.sh — Configure Paperless-ngx for Heartwood Craft
#
# Idempotent: checks for existing objects before creating.
# Usage: PAPERLESS_TOKEN=<your-token> ./setup-paperless.sh
#
set -euo pipefail

BASE_URL="${PAPERLESS_URL:-http://localhost:8102}"
API="${BASE_URL}/api"

if [[ -z "${PAPERLESS_TOKEN:-}" ]]; then
  echo "ERROR: Set PAPERLESS_TOKEN env var (Settings > Users > Generate Token)"
  exit 1
fi

AUTH="Authorization: Token ${PAPERLESS_TOKEN}"
CT="Content-Type: application/json"

# ─── Helpers ──────────────────────────────────────────────────────────────────

api_get() {
  curl -sf -H "$AUTH" "$API/$1" 2>/dev/null
}

api_post() {
  curl -sf -X POST -H "$AUTH" -H "$CT" -d "$2" "$API/$1" 2>/dev/null
}

# Get all pages of a paginated endpoint, return results array
api_get_all() {
  local endpoint="$1"
  local page=1
  local all_results="[]"
  while true; do
    local response
    response=$(curl -sf -H "$AUTH" "${API}/${endpoint}?page=${page}&page_size=100" 2>/dev/null) || break
    local results
    results=$(echo "$response" | jq -r '.results // []')
    all_results=$(echo "$all_results $results" | jq -s 'add')
    local next
    next=$(echo "$response" | jq -r '.next // "null"')
    if [[ "$next" == "null" ]]; then break; fi
    page=$((page + 1))
  done
  echo "$all_results"
}

find_by_name() {
  local json_array="$1"
  local name="$2"
  echo "$json_array" | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1
}

# ─── 1. Tags ─────────────────────────────────────────────────────────────────

echo "=== Creating Tags ==="

existing_tags=$(api_get_all "tags")

create_tag() {
  local name="$1"
  local color="${2:-#a6cee3}"
  local existing_id
  existing_id=$(find_by_name "$existing_tags" "$name")
  if [[ -n "$existing_id" ]]; then
    echo "  Tag '$name' already exists (id=$existing_id)"
    echo "$existing_id"
    return
  fi
  local result
  result=$(api_post "tags/" "{\"name\": \"$name\", \"color\": \"$color\", \"matching_algorithm\": 0}")
  local id
  id=$(echo "$result" | jq -r '.id')
  echo "  Created tag '$name' (id=$id)" >&2
  echo "$id"
}

# Parent tags (categories)
echo "Creating parent tags..."
BUSINESS_ID=$(create_tag "Business" "#1f78b4" 2>&1 | tee /dev/stderr | tail -1)
PERSONAL_ID=$(create_tag "Personal" "#33a02c" 2>&1 | tee /dev/stderr | tail -1)
JOB_ID=$(create_tag "Job" "#ff7f00" 2>&1 | tee /dev/stderr | tail -1)
TRADE_ID=$(create_tag "Trade" "#6a3d9a" 2>&1 | tee /dev/stderr | tail -1)
STATUS_ID=$(create_tag "Status" "#e31a1c" 2>&1 | tee /dev/stderr | tail -1)

# Refresh tags after creating parents
existing_tags=$(api_get_all "tags")

# Helper to create a child tag (is_inbox_tag=false)
create_child_tag() {
  local name="$1"
  local color="$2"
  local existing_id
  existing_id=$(find_by_name "$existing_tags" "$name")
  if [[ -n "$existing_id" ]]; then
    echo "  Tag '$name' already exists (id=$existing_id)"
    return
  fi
  local result
  result=$(api_post "tags/" "{\"name\": \"$name\", \"color\": \"$color\", \"matching_algorithm\": 0}")
  local id
  id=$(echo "$result" | jq -r '.id')
  echo "  Created tag '$name' (id=$id)"
}

echo "Creating Business child tags..."
for tag in Receipt Invoice Contract Permit Warranty Insurance Estimate; do
  create_child_tag "$tag" "#a6cee3"
done

echo "Creating Personal child tags..."
for tag in Tax Medical Home Vehicle Financial; do
  create_child_tag "$tag" "#b2df8a"
done

echo "Creating Trade child tags..."
for tag in Demo Framing Plumbing Electrical Tile Drywall Painting "Finish Carpentry" Admin; do
  create_child_tag "$tag" "#cab2d6"
done

echo "Creating Status child tags..."
for tag in Inbox Matched "Review Needed" "Pushed to JT" "Pushed to Firefly"; do
  create_child_tag "$tag" "#fb9a99"
done

# Note: Job tag has no children yet — they'll be added per active job

# ─── 2. Document Types ───────────────────────────────────────────────────────

echo ""
echo "=== Creating Document Types ==="

existing_types=$(api_get_all "document_types")

create_doc_type() {
  local name="$1"
  local match="$2"
  local algo="$3"  # 1=any, 2=all, 3=literal, 4=regex, 5=fuzzy, 6=auto
  local existing_id
  existing_id=$(find_by_name "$existing_types" "$name")
  if [[ -n "$existing_id" ]]; then
    echo "  Document type '$name' already exists (id=$existing_id)"
    return
  fi
  local result
  result=$(api_post "document_types/" "{\"name\": \"$name\", \"match\": \"$match\", \"matching_algorithm\": $algo}")
  local id
  id=$(echo "$result" | jq -r '.id')
  echo "  Created document type '$name' (id=$id)"
}

# matching_algorithm: 1=any word, 3=exact, 6=auto
create_doc_type "Receipt"                 "receipt,sales receipt,transaction"   1
create_doc_type "Vendor Invoice"          "invoice,inv #,invoice number"       1
create_doc_type "Purchase Order"          "purchase order,po #,p.o."           1
create_doc_type "Contract"                "contract,agreement,terms"           1
create_doc_type "Permit"                  "permit,building permit,inspection"  1
create_doc_type "Warranty"                "warranty,guarantee"                 1
create_doc_type "Insurance Certificate"   "certificate of insurance,COI,liability,insurance" 1
create_doc_type "Tax Document"            "W-9,1099,W-2,tax return,tax"       1

# ─── 3. Correspondents ───────────────────────────────────────────────────────

echo ""
echo "=== Creating Correspondents ==="

existing_correspondents=$(api_get_all "correspondents")

create_correspondent() {
  local name="$1"
  local match="$2"
  local algo="$3"
  local existing_id
  existing_id=$(find_by_name "$existing_correspondents" "$name")
  if [[ -n "$existing_id" ]]; then
    echo "  Correspondent '$name' already exists (id=$existing_id)"
    return
  fi
  local result
  result=$(api_post "correspondents/" "{\"name\": \"$name\", \"match\": \"$match\", \"matching_algorithm\": $algo}")
  local id
  id=$(echo "$result" | jq -r '.id')
  echo "  Created correspondent '$name' (id=$id)"
}

# matching_algorithm: 1=any word matches
create_correspondent "Kenyon Noble"          "kenyon noble,kenyon"        1
create_correspondent "Montana Tile & Stone"  "montana tile"               1
create_correspondent "Ferguson"              "ferguson"                   1
create_correspondent "Home Depot"            "home depot"                 1
create_correspondent "Lowe's"                "lowes,lowe's"               1
create_correspondent "Yellowstone Lumber"    "yellowstone lumber"         1

# ─── 4. Custom Fields ────────────────────────────────────────────────────────

echo ""
echo "=== Creating Custom Fields ==="

existing_fields=$(api_get_all "custom_fields")

create_custom_field() {
  local name="$1"
  local data_type="$2"  # string, monetary, integer, url, date, boolean, etc.
  local existing_id
  existing_id=$(find_by_name "$existing_fields" "$name")
  if [[ -n "$existing_id" ]]; then
    echo "  Custom field '$name' already exists (id=$existing_id)"
    return
  fi
  local result
  result=$(api_post "custom_fields/" "{\"name\": \"$name\", \"data_type\": \"$data_type\"}")
  local id
  id=$(echo "$result" | jq -r '.id')
  echo "  Created custom field '$name' (id=$id, type=$data_type)"
}

create_custom_field "jt_job_id"    "string"
create_custom_field "jt_job_name"  "string"
create_custom_field "amount"       "monetary"
create_custom_field "cost_code"    "string"
create_custom_field "n8n_status"   "string"
create_custom_field "firefly_id"   "string"

# ─── 5. Verification ─────────────────────────────────────────────────────────

echo ""
echo "=== Verification ==="

echo ""
echo "--- Tags ---"
api_get_all "tags" | jq -r '.[] | "  \(.id): \(.name)"'

echo ""
echo "--- Document Types ---"
api_get_all "document_types" | jq -r '.[] | "  \(.id): \(.name) [match: \(.match // "none")]"'

echo ""
echo "--- Correspondents ---"
api_get_all "correspondents" | jq -r '.[] | "  \(.id): \(.name) [match: \(.match // "none")]"'

echo ""
echo "--- Custom Fields ---"
api_get_all "custom_fields" | jq -r '.[] | "  \(.id): \(.name) (\(.data_type))"'

# ─── 6. Test Upload ──────────────────────────────────────────────────────────

echo ""
echo "=== Test Upload ==="

# Create a minimal test PDF
TEST_PDF="/tmp/paperless-test-receipt.pdf"
if command -v python3 &>/dev/null; then
  python3 -c "
# Minimal valid PDF with text for OCR testing
pdf_content = '''%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>>endobj
4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
5 0 obj<</Length 244>>
stream
BT
/F1 16 Tf
50 700 Td
(RECEIPT) Tj
/F1 12 Tf
0 -30 Td
(Kenyon Noble Building Materials) Tj
0 -20 Td
(Date: 2026-03-25) Tj
0 -20 Td
(Invoice #: KN-2026-0042) Tj
0 -20 Td
(2x4x8 Studs x 200 @ 4.29 = 858.00) Tj
0 -20 Td
(Total: \$858.00) Tj
ET
endstream
endobj
xref
0 6
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
0000000266 00000 n
0000000340 00000 n
trailer<</Size 6/Root 1 0 R>>
startxref
636
%%EOF'''
with open('$TEST_PDF', 'w') as f:
    f.write(pdf_content)
print('Test PDF created')
"
else
  echo "python3 not available, skipping test upload"
  exit 0
fi

if [[ -f "$TEST_PDF" ]]; then
  echo "Uploading test document..."
  UPLOAD_RESULT=$(curl -sf -X POST \
    -H "$AUTH" \
    -F "document=@${TEST_PDF}" \
    -F "title=Test Receipt - Kenyon Noble 2026-03-25" \
    "${API}/documents/post_document/" 2>/dev/null) || {
    echo "  Upload failed (might need multipart support). Try manually:"
    echo "  curl -X POST -H 'Authorization: Token <token>' -F 'document=@test.pdf' ${API}/documents/post_document/"
    exit 0
  }
  echo "  Upload response: $UPLOAD_RESULT"
  echo "  Document submitted for processing. Check Paperless UI in ~30s for:"
  echo "    - OCR text extraction"
  echo "    - Auto-matched correspondent: Kenyon Noble"
  echo "    - Auto-matched document type: Receipt"
  echo "    - Auto-tagged: Inbox (status)"
  rm -f "$TEST_PDF"
fi

echo ""
echo "=== Setup Complete ==="
echo "Paperless-ngx is configured for Heartwood Craft."
echo ""
echo "Next steps:"
echo "  1. Verify test document processed correctly in the Paperless UI"
echo "  2. Add Job child tags as new jobs come in"
echo "  3. Configure n8n workflows for automation (consume folder → n8n → Paperless)"
