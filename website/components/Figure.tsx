type FigureProps = {
  src: string;
  alt: string;
  caption?: string;
};

export function Figure({ src, alt, caption }: FigureProps) {
  const isVideo = src.endsWith(".mp4") || src.endsWith(".webm");
  return (
    <figure className="shot">
      {isVideo ? (
        <video src={src} controls playsInline muted loop aria-label={alt} />
      ) : (
        <img src={src} alt={alt} />
      )}
      {caption ? <figcaption>{caption}</figcaption> : null}
    </figure>
  );
}
