export function githubRepo(): string | null {
  const repo = process.env.NEXT_PUBLIC_GITHUB_REPO?.trim();
  return repo ? repo : null;
}

export function githubBranch(): string {
  const branch = process.env.NEXT_PUBLIC_GITHUB_BRANCH?.trim();
  return branch ? branch : "main";
}

export function sourceFileForPath(pathname: string): string {
  const path = pathname.replace(/\/+$/, "") || "/";
  if (path === "/") {
    return "website/app/page.tsx";
  }
  return `website/app${path}/page.mdx`;
}
