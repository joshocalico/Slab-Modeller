"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";

export function DocOutline() {
  const path = usePathname();
  const [expanded, setExpanded] = useState(false);
  const [headings, setHeadings] = useState<{ id: string; text: string }[]>([]);
  useEffect(() => {
    // Wait for the routed article to reach the DOM before reading its headings.
    const frame = requestAnimationFrame(() => {
      setHeadings([...document.querySelectorAll<HTMLElement>(".guide-main h2[id]")].map(heading => ({
        id: heading.id,
        text: heading.textContent || "Section",
      })));
    });
    return () => cancelAnimationFrame(frame);
  }, [path]);
  if (!headings.length) return null;
  return (
    <nav className="doc-outline" aria-label="On this page">
      <span className="eyebrow">On this page</span>
      <button className="outline-toggle" aria-expanded={expanded} aria-controls="page-sections" onClick={() => setExpanded(!expanded)}>
        On this page <span aria-hidden="true">{expanded ? "−" : "+"}</span>
      </button>
      <ol id="page-sections" className={expanded ? "is-open" : ""}>
        {headings.map(({ id, text }) => <li key={id}><a href={`#${id}`} onClick={() => setExpanded(false)}>{text}</a></li>)}
      </ol>
    </nav>
  );
}
