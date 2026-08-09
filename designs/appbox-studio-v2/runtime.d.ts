// Type shim for the server-provided runtime/ modules (not part of the artifact;
// `appbox design serve` injects them). Keep signatures in sync with the server runtime.
declare module '*runtime/icon.tsx' {
  import type { JSX } from 'hono/jsx';
  interface IconProps {
    name: string;
    size?: number;
    class?: string;
    cls?: string;
    label?: string;
  }
  export default function Icon(props: IconProps): JSX.Element;
}
