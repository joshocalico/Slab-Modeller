import type { ReactNode } from "react";
import "./globals.css";

export const metadata = {
  title: {
    default: "Slab",
    template: "%s · Slab",
  },
  description: "In-Godot 3D blockout. Half-edge solids, not AABB boxes.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
