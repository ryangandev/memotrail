import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "MemoTrail",
  description: "A private record of a life in progress.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
