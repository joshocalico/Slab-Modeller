import Image from "next/image";
import Link from "next/link";

export function SiteMark({ href = "/" }: { href?: string }) {
  return (
    <Link className="site-mark" href={href}>
      <Image src="/icon.svg" alt="" width={28} height={28} />
      Slab
    </Link>
  );
}
