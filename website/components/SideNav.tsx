"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { SiteMark } from "@/components/SiteMark";
import type { NavGroup } from "@/lib/nav";

export function SideNav({
  groups,
  label,
  otherHref,
  otherLabel,
}: {
  groups: NavGroup[];
  label: string;
  otherHref: string;
  otherLabel: string;
}) {
  const path = usePathname();
  return (
    <nav className="guide-nav" aria-label={label}>
      <SiteMark />
      {groups.map((group) => (
        <section key={group.title}>
          <h2>{group.title}</h2>
          <ul>
            {group.items.map((item) => (
              <li key={item.href}>
                <Link
                  href={item.href}
                  aria-current={path === item.href ? "page" : undefined}
                >
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ))}
      <p className="guide-nav-other">
        <Link href={otherHref}>{otherLabel}</Link>
      </p>
    </nav>
  );
}
