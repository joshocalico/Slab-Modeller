import { DocOutline } from "@/components/DocOutline";
import { DocFooter } from "@/components/DocFooter";
import { EditLink } from "@/components/EditLink";
import { SideNav } from "@/components/SideNav";
import { GUIDE_NAV } from "@/lib/nav";
import type { ReactNode } from "react";

export default function GuideLayout({ children }: { children: ReactNode }) {
  return (
    <div className="guide-shell">
      <SideNav
        groups={GUIDE_NAV}
        label="Guide"
        otherHref="/engineering"
        otherLabel="Engineering notes"
      />
      <main id="main-content" className="guide-main">
        <p className="eyebrow doc-section">Slab manual</p>
        {children}
        <DocFooter groups={GUIDE_NAV} />
        <EditLink />
      </main>
      <DocOutline />
    </div>
  );
}
