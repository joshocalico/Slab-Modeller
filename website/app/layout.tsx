import type { ReactNode } from "react";
import { Roboto_Slab } from "next/font/google";
import "./globals.css";

const robotoSlab = Roboto_Slab({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-display",
  display: "swap",
});

export const metadata = {
  title: {
    default: "Slab",
    template: "%s · Slab",
  },
  description: "Half-edge modeller for Godot. Closed solids with faces you can pull.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={robotoSlab.variable}>
      <body><a className="skip-link" href="#main-content">Skip to content</a>{children}</body>
    </html>
  );
}
