import forms from "@tailwindcss/forms"
import type { Config } from "tailwindcss"
import defaultTheme from "tailwindcss/defaultTheme"

// The template's tailwind.config.js, as ESM.
const config: Config = {
  content: ["./app/**/*.{js,ts,jsx,tsx}"],
  theme: {
    fontFamily: {
      sans: ["var(--font-inter)", ...defaultTheme.fontFamily.sans],
    },
    extend: {
      dropShadow: {
        cta: ["0 10px 15px rgba(219, 227, 248, 0.2)"],
        blue: ["0 10px 15px rgba(59, 130, 246, 0.2)"],
      },
    },
  },
  plugins: [forms],
}

export default config
