import { DocOutline } from "@/components/DocOutline";
import { DocFooter } from "@/components/DocFooter";
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
      <main id="main-content" className="guide-main">
        <p className="eyebrow doc-section">Inside the mesh</p>
        {children}
        <DocFooter groups={ENGINEERING_NAV} />
        <EditLink />
      </main>
      <DocOutline />
    </div>
  );
}
