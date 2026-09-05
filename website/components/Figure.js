export function Figure({ src, alt, caption }) {
  return (
    <figure className="shot">
      <img src={src} alt={alt} />
      {caption ? <figcaption>{caption}</figcaption> : null}
    </figure>
  );
}
