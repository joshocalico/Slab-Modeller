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
      <article className="guide-main">
        {children}
        <EditLink />
      </article>
    </div>
  );
}
