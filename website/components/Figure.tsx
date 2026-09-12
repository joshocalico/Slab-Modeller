import Image from "next/image";

type FigureProps = {
  src: string;
  alt: string;
  caption?: string;
  eager?: boolean;
};

export function Figure({ src, alt, caption, eager = false }: FigureProps) {
  const poster = src.includes("build-a-house") ? "/img/house-04.png" : src.includes("texture-a-room") ? "/img/solid-textured.png" : undefined;
  const isVideo = src.endsWith(".mp4") || src.endsWith(".webm");
  return (
    <figure className="shot">
      {isVideo ? (
        <video src={src} poster={poster} width={1280} height={720} preload="metadata" controls playsInline muted loop aria-label={alt} />
      ) : (
        <a className="figure-link" href={src} aria-label={`Open full-size image: ${alt}`}><Image loading={eager ? "eager" : "lazy"} src={src} alt={alt} width={1280} height={src.includes("panel") ? 340 : 720} sizes="(max-width: 800px) 100vw, 740px" /></a>
      )}
      {caption ? <figcaption>{caption}</figcaption> : null}
    </figure>
  );
}
