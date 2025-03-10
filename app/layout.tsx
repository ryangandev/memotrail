import './globals.css';

import { Geist, Geist_Mono } from 'next/font/google';

import type { Metadata } from 'next';
import { Toaster } from '@/components/ui/sonner';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: 'Memotrail',
  description:
    "Keep lessons close and milestones closer — capture life's journey, one note at a time.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} min-h-screen p-4 antialiased`}
      >
        {children}
        <Toaster />
      </body>
    </html>
  );
}
