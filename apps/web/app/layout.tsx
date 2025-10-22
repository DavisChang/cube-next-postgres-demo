export const metadata = {
  title: 'Analytics Demo',
  description: 'Cube + Next.js + Postgres demo'
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: 'Inter, system-ui, Arial', margin: 0 }}>{children}</body>
    </html>
  );
}
