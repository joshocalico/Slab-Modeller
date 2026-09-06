type FigureProps = {
  src: string;
  alt: string;
  caption?: string;
};

export function Figure({ src, alt, caption }: FigureProps) {
  return (
    <figure className="shot">
      <img src={src} alt={alt} />
      {caption ? <figcaption>{caption}</figcaption> : null}
    </figure>
  );
}
