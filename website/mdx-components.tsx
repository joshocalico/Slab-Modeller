import { Children, isValidElement, type ReactNode } from "react";
import type { MDXComponents } from "mdx/types";

function headingText(children: ReactNode): string {
  return Children.toArray(children).map(child => {
    if (typeof child === "string" || typeof child === "number") return String(child);
    if (isValidElement<{ children?: ReactNode }>(child)) return headingText(child.props.children);
    return "";
  }).join("");
}

export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    h2: ({ children, ...props }) => {
      const id = headingText(children).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
      return <h2 id={id} {...props}>{children}</h2>;
    },
    table: (props) => <div className="guide-table" tabIndex={0} role="region" aria-label="Scrollable reference table"><table {...props} /></div>,
    ...components,
  };
}
