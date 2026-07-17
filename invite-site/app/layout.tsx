import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Приглашение в OneCart",
  description:
    "Откройте общий семейный список покупок в приложении OneCart.",
  applicationName: "OneCart",
  referrer: "no-referrer",
  robots: {
    index: false,
    follow: false,
    nocache: true,
  },
  openGraph: {
    type: "website",
    locale: "ru_RU",
    siteName: "OneCart",
    title: "Приглашение в OneCart",
    description:
      "Откройте общий семейный список покупок в приложении OneCart.",
  },
  icons: {
    icon: "/onecart-mark.svg",
    shortcut: "/onecart-mark.svg",
    apple: "/onecart-app-icon.png",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f5f6f3" },
    { media: "(prefers-color-scheme: dark)", color: "#111713" },
  ],
  colorScheme: "light dark",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ru">
      <body>{children}</body>
    </html>
  );
}
