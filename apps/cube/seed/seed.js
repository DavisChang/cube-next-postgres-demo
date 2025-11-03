/**
 * Seed script for generating synthetic analytics events for the last N days.
 * Defaults:
 *  - SEED_DAYS=180
 *  - ROWS_PER_DAY=1000
 *  - BATCH_SIZE=5000
 * Connection via PG* envs (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE).
 */
const { Client } = require('pg');

const DAYS = parseInt(process.env.SEED_DAYS || '180', 10);
const ROWS_PER_DAY = parseInt(process.env.ROWS_PER_DAY || '1000', 10);
const BATCH_SIZE = parseInt(process.env.BATCH_SIZE || '5000', 10);

// user pool determines distinct user_id count and repeat probability
const USER_POOL = parseInt(process.env.USER_POOL || '50000', 10);

const REGIONS = ['TW','US','JP','DE','FR','GB','CA','AU','BR','IN','SG','NL','SE','MX'];
const DEVICES = ['mobile','desktop','tablet','smart_tv','console'];
const SOURCES = ['direct','google','email','social','affiliate','bing','partner','community'];
const CAMPAIGNS = {
  direct: ['Homepage Refresh', 'Organic Loyalty'],
  google: ['Search Core', 'Brand Retargeting', 'Product Launch SEM'],
  email: ['Lifecycle Nurture', 'Product Update Blast', 'Winback Journey'],
  social: ['Influencer Sprint', 'Viral Challenge', 'Stories Countdown'],
  affiliate: ['Affiliate Gold', 'Deal Sites Push'],
  bing: ['Bing Ads Seasonal'],
  partner: ['Strategic Alliance', 'Marketplace Spotlight'],
  community: ['Community AMA', 'Open Source Drive'],
};
const EVENT_TYPES = ['page_view', 'signup', 'purchase', 'upgrade', 'support'];

function randWeighted(options) {
  const total = options.reduce((sum, [, weight]) => sum + weight, 0);
  let roll = Math.random() * total;
  for (const [value, weight] of options) {
    if ((roll -= weight) <= 0) return value;
  }
  return options[options.length - 1][0];
}

function campaignForSource(source) {
  const list = CAMPAIGNS[source] || ['General Awareness'];
  return randChoice(list);
}

function randChoice(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

// Skewed revenue: 25% zero, otherwise ~lognormal
function randomRevenue(scale = 20) {
  if (Math.random() < 0.25) return 0;
  const u = Math.random();
  const v = Math.random();
  const z = Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
  const logValue = Math.exp(0.5 * z) * scale;
  return Math.round(logValue * 100) / 100;
}

// Session duration (sec): approx gamma-like using sum of exponentials
function randomSessionSeconds() {
  const k = 3;
  let sum = 0;
  for (let i = 0; i < k; i++) sum += -Math.log(1 - Math.random());
  const seconds = Math.max(5, Math.min(3600, Math.round(sum * 60)));
  return seconds;
}

function randomTimestampWithinDay(dayDate) {
  const start = new Date(dayDate);
  const secs = Math.floor(Math.random() * 86400);
  start.setSeconds(start.getSeconds() + secs);
  return start;
}

function randomEventType() {
  return randWeighted([
    ['page_view', 50],
    ['signup', 18],
    ['purchase', 18],
    ['upgrade', 10],
    ['support', 4],
  ]);
}

function planForEvent(eventType) {
  switch (eventType) {
    case 'signup':
      return randWeighted([
        ['free', 60],
        ['basic', 30],
        ['pro', 10],
      ]);
    case 'purchase':
      return randWeighted([
        ['basic', 55],
        ['pro', 35],
        ['enterprise', 10],
      ]);
    case 'upgrade':
      return randWeighted([
        ['pro', 60],
        ['enterprise', 40],
      ]);
    case 'support':
      return randWeighted([
        ['basic', 40],
        ['pro', 40],
        ['enterprise', 20],
      ]);
    default:
      return randWeighted([
        ['free', 40],
        ['basic', 30],
        ['pro', 20],
        ['enterprise', 10],
      ]);
  }
}

function revenueForEvent(eventType) {
  switch (eventType) {
    case 'purchase':
      return randomRevenue(60);
    case 'upgrade':
      return randomRevenue(120);
    default:
      return 0;
  }
}

function sessionForEvent(eventType) {
  let seconds = randomSessionSeconds();
  if (eventType === 'support') seconds = Math.min(3600, Math.round(seconds * 1.8));
  if (eventType === 'page_view') seconds = Math.round(seconds * 0.7 + Math.random() * 30);
  return seconds;
}

async function ensureTable(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS public.events (
      event_time TIMESTAMP NOT NULL,
      region TEXT,
      device TEXT,
      source TEXT,
      campaign TEXT,
      event_type TEXT,
      plan TEXT,
      user_id BIGINT,
      revenue NUMERIC(18,2),
      session_duration_seconds INT
    );
  `);
  await client.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS campaign TEXT;`);
  await client.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS event_type TEXT;`);
  await client.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS plan TEXT;`);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_events_time ON public.events(event_time);`);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_events_region ON public.events(region);`);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_events_device ON public.events(device);`);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_events_source ON public.events(source);`);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_events_campaign ON public.events(campaign);`);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_events_event_type ON public.events(event_type);`);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_events_plan ON public.events(plan);`);
}

async function seed() {
  const client = new Client({
    host: process.env.PGHOST || 'localhost',
    port: parseInt(process.env.PGPORT || '5432', 10),
    user: process.env.PGUSER || 'analytics',
    password: process.env.PGPASSWORD || 'pass',
    database: process.env.PGDATABASE || 'analytics',
  });
  await client.connect();

  console.log(`Connected to ${client.host}:${client.port}/${client.database}`);
  await ensureTable(client);

  if ((process.env.CLEAN || 'false').toLowerCase() === 'true') {
    console.log('Cleaning existing rows from public.events ...');
    await client.query('TRUNCATE TABLE public.events;');
  }

  console.log(`Seeding ${DAYS} days × ~${ROWS_PER_DAY} rows/day (batch ${BATCH_SIZE}) ...`);

  const today = new Date();
  const startDate = new Date(today);
  startDate.setDate(startDate.getDate() - (DAYS - 1));
  startDate.setHours(0,0,0,0);

  let total = 0;

  for (let d = 0; d < DAYS; d++) {
    const day = new Date(startDate);
    day.setDate(startDate.getDate() + d);

    const rowsForDay = ROWS_PER_DAY;
    let batchValues = [];
    const columnsPerRow = 10;

    async function flush() {
      if (!batchValues.length) return;
      const placeholders = [];
      for (let i = 0; i < batchValues.length; i += columnsPerRow) {
        placeholders.push(
          `($${i+1}, $${i+2}, $${i+3}, $${i+4}, $${i+5}, $${i+6}, $${i+7}, $${i+8}, $${i+9}, $${i+10})`
        );
      }
      const sql = `INSERT INTO public.events
        (event_time, region, device, source, campaign, event_type, plan, user_id, revenue, session_duration_seconds)
        VALUES ${placeholders.join(',')};`;
      await client.query(sql, batchValues);
      batchValues = [];
    }

    for (let i = 0; i < rowsForDay; i++) {
      const ts = randomTimestampWithinDay(day);
      const region = randChoice(REGIONS);
      const device = randChoice(DEVICES);
      const source = randChoice(SOURCES);
      const campaign = campaignForSource(source);
      const event_type = randomEventType();
      const plan = planForEvent(event_type);
      const user_id = 100000 + Math.floor(Math.random() * USER_POOL);
      const revenue = revenueForEvent(event_type);
      const sess = sessionForEvent(event_type);

      batchValues.push(
        ts,
        region,
        device,
        source,
        campaign,
        event_type,
        plan,
        user_id,
        revenue,
        sess
      );

      if (batchValues.length >= BATCH_SIZE * columnsPerRow) {
        await flush();
      }
    }
    await flush();
    total += rowsForDay;
    if ((d + 1) % 10 === 0 || d === DAYS - 1) {
      console.log(`  - Day ${d+1}/${DAYS} inserted. Total rows ~= ${total}`);
    }
  }

  console.log(`✅ Seeding done. Total inserted ~= ${total}`);
  await client.end();
}

seed().catch((e) => {
  console.error('Seed failed:', e);
  process.exit(1);
});
