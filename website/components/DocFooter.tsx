"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { NavGroup } from "@/lib/nav";

export function DocFooter({ groups }: { groups: NavGroup[] }) {
  const path = usePathname();
  const pages = groups.flatMap(group => group.items);
  const index = pages.findIndex(page => page.href === path);
  const previous = pages[index - 1];
  const next = pages[index + 1];
  if (index < 0) return null;
  return <nav className="doc-footer" aria-label="More in this section">
    {previous ? <Link href={previous.href}><span>Previous</span>{previous.label}</Link> : <div />}
    {next ? <Link href={next.href}><span>Next</span>{next.label} <b aria-hidden="true">↗</b></Link> : null}
  </nav>;
}
