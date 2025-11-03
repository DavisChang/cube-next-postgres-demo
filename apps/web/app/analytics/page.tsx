"use client";

import React, { useEffect, useMemo, useState } from "react";
import cubejs from "@cubejs-client/core";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
} from "recharts";

const baseUrl = process.env.NEXT_PUBLIC_CUBEJS_API?.replace(/\/+$/, "");
const apiUrl = baseUrl ? `${baseUrl}/cubejs-api/v1` : "/cubejs-api/v1";
const token = process.env.NEXT_PUBLIC_CUBEJS_TOKEN || "DEV_TOKEN";
const cube = cubejs(token, { apiUrl });

type Mode = "ranking" | "series";
type Row = {
  name: string;
  dim?: string;
  day?: string;
  pv?: number;
  uv?: number;
  revenue?: number;
  avg_session?: number;
  signups?: number;
  purchases?: number;
  upgrades?: number;
};

const DIMENSIONS = [
  { value: "events.region", label: "Region" },
  { value: "events.device", label: "Device" },
  { value: "events.source", label: "Source" },
  { value: "events.campaign", label: "Campaign" },
  { value: "events.event_type", label: "Event Type" },
  { value: "events.plan", label: "Plan" },
];

const METRICS = [
  { value: "events.pv", label: "PV" },
  { value: "events.uv", label: "UV" },
  { value: "events.revenue", label: "Revenue" },
  { value: "events.avg_session", label: "Avg Session (s)" },
  { value: "events.signups", label: "Signups" },
  { value: "events.purchases", label: "Purchases" },
  { value: "events.upgrades", label: "Upgrades" },
];

const DEFAULT_METRICS = ["events.pv"];
const METRIC_LABELS = METRICS.reduce<Record<string, string>>((acc, item) => {
  acc[item.value] = item.label;
  return acc;
}, {});

export default function AnalyticsPage() {
  const [dimension, setDimension] = useState("events.region");
  const [metrics, setMetrics] = useState<string[]>(DEFAULT_METRICS);
  const [mode, setMode] = useState<Mode>("ranking");
  const [start, setStart] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() - 179);
    return d.toISOString().slice(0, 10);
  });
  const [end, setEnd] = useState(() => new Date().toISOString().slice(0, 10));
  const [rows, setRows] = useState<Row[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const activeMetrics = metrics.length ? metrics : DEFAULT_METRICS;
      const timeDimensions: any[] = [
        {
          dimension: "events.event_time",
          dateRange: [start, end],
          ...(mode === "series" ? { granularity: "day" } : {}),
        },
      ];
      const query: any = {
        measures: activeMetrics,
        dimensions: [dimension],
        timeDimensions,
        order: { [activeMetrics[0]]: "desc" as const },
        ...(mode === "ranking" ? { limit: 100 } : {}),
      };
      const rs = await cube.load(query);
      const pivot = rs.tablePivot();
      const out: Row[] = pivot.map((r: any) => {
        const name =
          mode === "series"
            ? `${r["events.event_time.day"]} · ${r[dimension]}`
            : r[dimension];
        const o: any = { name, dim: r[dimension] };
        activeMetrics.forEach((m) => {
          o[m.split(".").pop()!] = Number(r[m]);
        });
        if (mode === "series") o.day = r["events.event_time.day"];
        return o as Row;
      });
      setRows(out);
    } catch (err) {
      console.error("Failed to load analytics data", err);
      setError(
        err instanceof Error
          ? err.message
          : "Unable to load analytics data. Please try again."
      );
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  const activeMetrics = metrics.length ? metrics : DEFAULT_METRICS;
  const chartData = useMemo(() => rows, [rows]);
  const primaryMetricValue = activeMetrics[0] || DEFAULT_METRICS[0];
  const primaryMetricKey = primaryMetricValue.split(".").pop() || "pv";
  const primaryMetricLabel = METRIC_LABELS[primaryMetricValue] || primaryMetricKey.toUpperCase();

  return (
    <main
      style={{
        maxWidth: 1100,
        margin: "40px auto",
        fontFamily: "Inter, system-ui, Arial",
      }}
    >
      <h2 style={{ marginBottom: 12 }}>Analytics (Cube)</h2>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(6, minmax(120px, 1fr))",
          gap: 12,
          marginBottom: 16,
        }}
      >
        <label>
          Dimension
          <select
            value={dimension}
            onChange={(e) => setDimension(e.target.value)}
            style={{ width: "100%" }}
          >
            {DIMENSIONS.map((d) => (
              <option key={d.value} value={d.value}>
                {d.label}
              </option>
            ))}
          </select>
        </label>

        <label>
          Metrics (multi)
          <select
            multiple
            value={metrics}
            onChange={(e) =>
              setMetrics(() => {
                const next = Array.from(e.target.selectedOptions).map(
                  (o) => o.value
                );
                return next.length ? next : DEFAULT_METRICS;
              })
            }
            style={{ width: "100%", height: 84 }}
          >
            {METRICS.map((m) => (
              <option key={m.value} value={m.value}>
                {m.label}
              </option>
            ))}
          </select>
        </label>

        <label>
          Mode
          <select
            value={mode}
            onChange={(e) => setMode(e.target.value as Mode)}
            style={{ width: "100%" }}
          >
            <option value="ranking">Ranking</option>
            <option value="series">Time Series</option>
          </select>
        </label>

        <label>
          Start
          <input
            type="date"
            value={start}
            max={end}
            onChange={(e) => setStart(e.target.value)}
          />
        </label>

        <label>
          End
          <input
            type="date"
            value={end}
            min={start}
            onChange={(e) => setEnd(e.target.value)}
          />
        </label>

        <div style={{ display: "flex", alignItems: "end" }}>
          <button
            onClick={load}
            disabled={loading}
            style={{ padding: "8px 12px", borderRadius: 10 }}
          >
            {loading ? "Loading…" : "Load"}
          </button>
        </div>
      </div>

      <div
        style={{
          height: 420,
          background: "#fafafa",
          border: "1px solid #eee",
          borderRadius: 12,
          padding: 12,
        }}
      >
        <ResponsiveContainer width="100%" height="100%">
          {mode === "ranking" ? (
            <BarChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="dim" />
              <YAxis />
              <Tooltip />
              <Legend />
              {activeMetrics.map((m) => {
                const key = m.split(".").pop()!;
                const label = METRIC_LABELS[m] || key.toUpperCase();
                return <Bar key={m} dataKey={key} name={label} />;
              })}
            </BarChart>
          ) : (
            <LineChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="name" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Line
                type="monotone"
                dataKey={primaryMetricKey}
                name={primaryMetricLabel}
                dot={false}
              />
            </LineChart>
          )}
        </ResponsiveContainer>
      </div>

      {error ? (
        <p style={{ color: "#d00", marginTop: 12 }}>{error}</p>
      ) : null}

      <p style={{ color: "#666", marginTop: 12 }}>
        Tip: the default date range is the latest 180 days, but you can adjust
        it freely.
      </p>
    </main>
  );
}
