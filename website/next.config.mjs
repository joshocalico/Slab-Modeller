import createMDX from "@next/mdx";

const nextConfig = {
  output: "export",
  images: { unoptimized: true },
  pageExtensions: ["js", "jsx", "md", "mdx"],
};

const withMDX = createMDX({});

export default withMDX(nextConfig);
