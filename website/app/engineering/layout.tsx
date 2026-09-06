import { EditLink } from "@/components/EditLink";
import { SideNav } from "@/components/SideNav";
import { ENGINEERING_NAV } from "@/lib/nav";
import type { ReactNode } from "react";

export default function EngineeringLayout({ children }: { children: ReactNode }) {
  return (
    <div className="guide-shell">
      <SideNav
        groups={ENGINEERING_NAV}
        label="Engineering"
        otherHref="/guide"
        otherLabel="Back to the guide"
      />
      <article className="guide-main">
        {children}
        <EditLink />
      </article>
    </div>
  );
}
