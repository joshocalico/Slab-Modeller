"use client";

import { useState } from "react";
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
  const [expanded, setExpanded] = useState(false);
  return (
    <nav className="guide-nav" aria-label={label}>
      <SiteMark />
      <button className="nav-toggle" aria-expanded={expanded} aria-controls="nav-groups" onClick={() => setExpanded(!expanded)}>{label} contents <span aria-hidden="true">{expanded ? "−" : "+"}</span></button>
      <div id="nav-groups" className={`nav-groups ${expanded ? "is-open" : ""}`}>
      {groups.map((group) => (
        <section key={group.title}>
          <h2>{group.title}</h2>
          <ul>
            {group.items.map((item) => (
              <li key={item.href}>
                <Link
                  href={item.href}
                  onClick={() => setExpanded(false)}
                  aria-current={path === item.href ? "page" : undefined}
                >
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ))}
      </div>
      <p className="guide-nav-other">
        <Link href={otherHref}>{otherLabel}</Link>
      </p>
    </nav>
  );
}
