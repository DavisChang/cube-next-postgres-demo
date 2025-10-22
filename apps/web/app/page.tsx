import Link from "next/link";

export default function Home() {
  return (
    <main style={{ maxWidth: 800, margin: "80px auto", padding: 24 }}>
      <h1 style={{ marginBottom: 12 }}>Cube + Next.js + Postgres</h1>
      <p>
        This is the example homepage. Head over to the Analytics page to try the
        interactive charts.
      </p>
      <ul>
        <li>
          <Link href="/analytics">/analytics</Link>
        </li>
      </ul>
      <p style={{ color: "#666", marginTop: 24 }}>
        Tip: start Docker Postgres, run the seed script, then boot Cube and the
        frontend.
      </p>
    </main>
  );
}
