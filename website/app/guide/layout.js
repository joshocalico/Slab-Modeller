import { GuideNav } from "@/components/GuideNav";

export default function GuideLayout({ children }) {
  return (
    <div className="guide-shell">
      <GuideNav />
      <article className="guide-main">{children}</article>
    </div>
  );
}
