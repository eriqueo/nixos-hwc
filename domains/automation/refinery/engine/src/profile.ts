import { parse as parseYaml, YAMLParseError } from "yaml";
import { Profile, ProfileSchema } from "./contracts.js";
import { InvalidProfileError } from "./errors.js";

export function parseProfile(yamlText: string): Profile {
  let raw: unknown;
  try {
    raw = parseYaml(yamlText);
  } catch (err) {
    const msg =
      err instanceof YAMLParseError ? err.message : (err as Error).message;
    throw new InvalidProfileError(`profile YAML is unparseable: ${msg}`, [
      { path: [], message: msg },
    ]);
  }
  const result = ProfileSchema.safeParse(raw);
  if (!result.success) {
    throw new InvalidProfileError(
      "profile failed schema validation",
      result.error.issues,
    );
  }
  return result.data;
}

export type ProfileLoader = (source: string) => Promise<string>;

export async function loadProfile(
  source: string,
  loader: ProfileLoader,
): Promise<Profile> {
  const text = await loader(source);
  return parseProfile(text);
}
