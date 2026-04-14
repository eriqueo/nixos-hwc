module.exports = function(eleventyConfig) {
  // Passthrough copy
  eleventyConfig.addPassthroughCopy("src/css");
  eleventyConfig.addPassthroughCopy("src/js");
  eleventyConfig.addPassthroughCopy("src/img");
  eleventyConfig.addPassthroughCopy("src/_redirects");
  eleventyConfig.addPassthroughCopy("src/.htaccess");

  // Blog collection sorted by date
  eleventyConfig.addCollection("blog", function(collectionApi) {
    return collectionApi.getFilteredByGlob("src/blog/**/*.md")
      .sort((a, b) => b.date - a.date);
  });

  // Year shortcode for copyright
  eleventyConfig.addShortcode("year", () => `${new Date().getFullYear()}`);

  // Filters
  eleventyConfig.addFilter("dateReadable", (date) => {
    return new Date(date).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
  });
  eleventyConfig.addFilter("dateISO", (date) => new Date(date).toISOString());
  eleventyConfig.addFilter("head", (array, n) => array.slice(0, n));
  eleventyConfig.addFilter("rejectByUrl", (array, url) => array.filter(p => p.url !== url));
  eleventyConfig.addFilter("divide", (num, d) => num / d);
  eleventyConfig.addFilter("round", (num) => Math.ceil(num));
  eleventyConfig.addFilter("wordCount", (content) => {
    if (!content) return 0;
    return content.split(/\s+/).filter(Boolean).length;
  });

  return {
    dir: {
      input: "src",
      output: "dist",
      includes: "_includes",
      data: "_data"
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk"
  };
};
