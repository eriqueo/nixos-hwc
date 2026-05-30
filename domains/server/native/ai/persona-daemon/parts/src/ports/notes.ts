export interface NoteSource {
  /** Yield every indexable note's relative path + mtime. */
  list(): AsyncIterable<{ path: string; mtime: number }>;

  /** Read full note text by relative path. */
  read(path: string): Promise<string>;
}
