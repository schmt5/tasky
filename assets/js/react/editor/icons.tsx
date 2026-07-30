// The custom SVG icons of the editor toolbar (everything the heroicons set
// doesn't cover: answer-field types and table operations).

interface IconProps {
  className?: string;
}

export function TextColorIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M6 19 L12 5 L18 19" />
      <path d="M8.5 14 H15.5" />
    </svg>
  );
}

export function FreitextIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <text
        x="2"
        y="18"
        fontFamily="Fraunces, serif"
        fontStyle="italic"
        fontWeight="500"
        fontSize="18"
        fill="currentColor"
        stroke="none"
      >
        A
      </text>
      <path d="M13 9h8M13 13h8M13 17h5" />
    </svg>
  );
}

export function FreitextAbcIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <text
        x="3"
        y="16"
        fontFamily="Fraunces, serif"
        fontStyle="italic"
        fontWeight="400"
        fontSize="15"
        fill="currentColor"
        stroke="none"
      >
        abc
      </text>
      <path d="M3 20h14" strokeWidth="1.4" opacity="0.5" />
    </svg>
  );
}

export function LueckentextIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M3 10h4M17 10h4" />
      <rect
        x="9"
        y="7"
        width="6"
        height="6"
        rx="1"
        fill="currentColor"
        opacity="0.18"
        stroke="none"
      />
      <rect x="9" y="7" width="6" height="6" rx="1" />
      <path d="M3 17h18" opacity="0.4" />
    </svg>
  );
}

export function MultipleChoiceIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="6" cy="7" r="2.2" />
      <circle cx="6" cy="17" r="2.2" />
      <circle cx="6" cy="17" r="0.8" fill="currentColor" stroke="none" />
      <path d="M11 7h9M11 17h9" />
    </svg>
  );
}

export function AddRowAboveIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="10" width="18" height="10" rx="1.5" />
      <line x1="3" y1="15" x2="21" y2="15" />
      <line x1="9" y1="10" x2="9" y2="20" />
      <line x1="15" y1="10" x2="15" y2="20" />
      <path d="M12 3v5" strokeWidth="1.8" />
      <path d="M9.5 5.5L12 3l2.5 2.5" strokeWidth="1.8" />
    </svg>
  );
}

export function AddRowBelowIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="10" rx="1.5" />
      <line x1="3" y1="9" x2="21" y2="9" />
      <line x1="9" y1="4" x2="9" y2="14" />
      <line x1="15" y1="4" x2="15" y2="14" />
      <path d="M12 21v-5" strokeWidth="1.8" />
      <path d="M9.5 18.5L12 21l2.5-2.5" strokeWidth="1.8" />
    </svg>
  );
}

export function RemoveRowIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="16" rx="1.5" />
      <line x1="3" y1="9.33" x2="21" y2="9.33" />
      <line x1="9" y1="4" x2="9" y2="20" />
      <line x1="15" y1="4" x2="15" y2="20" />
      <rect
        x="3"
        y="9.33"
        width="18"
        height="5.33"
        fill="currentColor"
        opacity="0.14"
        stroke="none"
      />
      <line x1="5" y1="14.66" x2="21" y2="14.66" />
      <path d="M5 12l14 0" strokeWidth="2" opacity="0.9" />
    </svg>
  );
}

export function AddColumnLeftIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="9" y="4" width="12" height="16" rx="1.5" />
      <line x1="9" y1="9.33" x2="21" y2="9.33" />
      <line x1="9" y1="14.66" x2="21" y2="14.66" />
      <line x1="15" y1="4" x2="15" y2="20" />
      <path d="M3 12h5" strokeWidth="1.8" />
      <path d="M5.5 9.5L3 12l2.5 2.5" strokeWidth="1.8" />
    </svg>
  );
}

export function AddColumnRightIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="12" height="16" rx="1.5" />
      <line x1="3" y1="9.33" x2="15" y2="9.33" />
      <line x1="3" y1="14.66" x2="15" y2="14.66" />
      <line x1="9" y1="4" x2="9" y2="20" />
      <path d="M21 12h-5" strokeWidth="1.8" />
      <path d="M18.5 9.5L21 12l-2.5 2.5" strokeWidth="1.8" />
    </svg>
  );
}

export function RemoveColumnIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="16" rx="1.5" />
      <line x1="3" y1="9.33" x2="21" y2="9.33" />
      <line x1="3" y1="14.66" x2="21" y2="14.66" />
      <line x1="9" y1="4" x2="9" y2="20" />
      <line x1="15" y1="4" x2="15" y2="20" />
      <rect
        x="9"
        y="4"
        width="6"
        height="16"
        fill="currentColor"
        opacity="0.14"
        stroke="none"
      />
      <path d="M12 6v16" strokeWidth="2" opacity="0.9" />
    </svg>
  );
}

export function HeaderRowIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="16" rx="1.5" />
      <path
        d="M3 5.5a1.5 1.5 0 0 1 1.5-1.5h15a1.5 1.5 0 0 1 1.5 1.5v3.83h-18z"
        fill="currentColor"
        opacity="0.22"
        stroke="none"
      />
      <line x1="3" y1="9.33" x2="21" y2="9.33" strokeWidth="1.8" />
      <line x1="3" y1="14.66" x2="21" y2="14.66" />
      <line x1="9" y1="9.33" x2="9" y2="20" />
      <line x1="15" y1="9.33" x2="15" y2="20" />
    </svg>
  );
}

export function RemoveTableIcon({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="16" rx="1.5" opacity="0.45" />
      <line x1="3" y1="9.33" x2="21" y2="9.33" opacity="0.45" />
      <line x1="3" y1="14.66" x2="21" y2="14.66" opacity="0.45" />
      <line x1="9" y1="4" x2="9" y2="20" opacity="0.45" />
      <line x1="15" y1="4" x2="15" y2="20" opacity="0.45" />
      <circle
        cx="18"
        cy="18"
        r="4.5"
        fill="var(--panel, #fff)"
        stroke="currentColor"
        strokeWidth="1.5"
      />
      <path d="M16 16l4 4M20 16l-4 4" strokeWidth="1.6" />
    </svg>
  );
}

