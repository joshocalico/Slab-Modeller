export type NavItem = {
  href: string;
  label: string;
};

export type NavGroup = {
  title: string;
  items: NavItem[];
};

export const GUIDE_NAV: NavGroup[] = [
  {
    title: "Start",
    items: [
      { href: "/guide", label: "The guide" },
      { href: "/guide/install", label: "Install Slab" },
    ],
  },
  {
    title: "Tutorial",
    items: [
      {
        href: "/guide/tutorials/block-out-a-room",
        label: "Block out a room",
      },
      {
        href: "/guide/tutorials/texture-a-room",
        label: "Texture a room",
      },
      {
        href: "/guide/tutorials/build-a-house",
        label: "Build a house",
      },
    ],
  },
  {
    title: "How to",
    items: [
      {
        href: "/guide/how-to/create-a-solid",
        label: "Create a solid",
      },
      {
        href: "/guide/how-to/select-in-the-view",
        label: "Select in the 3D view",
      },
      { href: "/guide/how-to/pull-a-wall", label: "Pull a wall" },
      { href: "/guide/how-to/punch-a-cavity", label: "Punch a cavity" },
    ],
  },
  {
    title: "Reference",
    items: [
      { href: "/guide/reference/keys-and-modes", label: "Keys and modes" },
      { href: "/guide/reference/panel", label: "The Slab panel" },
    ],
  },
  {
    title: "Explanation",
    items: [
      { href: "/guide/explanation/closed-solids", label: "Closed solids" },
    ],
  },
];

export const ENGINEERING_NAV: NavGroup[] = [
  {
    title: "Engineering",
    items: [
      { href: "/engineering", label: "This section" },
      { href: "/engineering/half-edge-meshes", label: "Half-edge meshes" },
      { href: "/engineering/mesh-booleans", label: "Mesh booleans" },
    ],
  },
];
