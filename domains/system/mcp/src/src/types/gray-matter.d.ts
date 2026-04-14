declare module "gray-matter" {
  interface GrayMatterFile {
    data: Record<string, unknown>;
    content: string;
    excerpt?: string;
    orig: string | Buffer;
    language: string;
    matter: string;
    stringify(lang?: string): string;
  }

  interface GrayMatterOption {
    excerpt?: boolean | ((file: GrayMatterFile, options: GrayMatterOption) => void);
    excerpt_separator?: string;
    engines?: Record<string, unknown>;
    language?: string;
    delimiters?: string | [string, string];
  }

  function matter(input: string | Buffer, options?: GrayMatterOption): GrayMatterFile;

  namespace matter {
    function stringify(content: string, data: Record<string, unknown>, options?: GrayMatterOption): string;
  }

  export = matter;
}
