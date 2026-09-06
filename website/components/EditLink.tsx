"use client";

import { githubBranch, githubRepo, sourceFileForPath } from "@/lib/github";
import { usePathname } from "next/navigation";

export function EditLink() {
  const repo = githubRepo();
  const path = usePathname();
  if (!repo) {
    return null;
  }
  const href = `https://github.com/${repo}/edit/${githubBranch()}/${sourceFileForPath(path)}`;
  return (
    <p className="edit-on-github">
      <a href={href}>Edit on GitHub</a>
    </p>
  );
}
