export type GlossaryEntry =
  | string
  | {
      definition: string;
      url?: string;
      urlLabel?: string;
    };

/**
 * Glossary keys are lowercase kebab-case, sorted alphabetically.
 * Keep this list in lockstep with .kiro/steering/glossary.md.
 */
export const glossary: Record<string, GlossaryEntry> = {
  channel:
    "Delivery channel created with create-channel. The console labels the same resource S3 general purpose delivery.",
  "data-freshness":
    "Buffer window before records land in S3. DataFreshnessInSeconds accepts 300–900 seconds (5–15 minutes); default 300.",
  dlq: "Dead-letter queue for failed deliveries. Optional for S3 general purpose; when omitted, failures land in the destination bucket under an error prefix.",
  kds: "Amazon Kinesis Data Streams — the source stream that hosts the delivery channel.",
  "on-demand-advantage":
    "On-Demand capacity mode tier that supports S3 delivery. Provisioned streams cannot host a channel.",
  "on-demand-standard":
    "On-Demand capacity mode tier that supports S3 delivery. Provisioned streams cannot host a channel.",
  "output-key-template":
    "S3 object key pattern for delivered records. When compression is enabled the template must end with an extension placeholder.",
  "service-execution-role":
    "IAM role assumed by kinesis.amazonaws.com to write objects. Trust policy uses aws:SourceAccount and aws:SourceArn matching channel/*.",
  shard:
    "Unit of capacity in a Kinesis stream. Delivery does not consume the stream's read throughput or enhanced fan-out slots.",
  "streaming-tables":
    "Separate Kinesis delivery destination for Apache Iceberg on S3 Tables. Out of scope for this walkthrough; a stream may host at most one S3 general purpose delivery and one streaming-tables delivery.",
};

export function resolveGlossaryEntry(entry: GlossaryEntry | undefined) {
  if (!entry) return { definition: undefined, url: undefined, urlLabel: undefined };
  if (typeof entry === "string") {
    return { definition: entry, url: undefined, urlLabel: undefined };
  }
  return {
    definition: entry.definition,
    url: entry.url,
    urlLabel: entry.urlLabel ?? entry.url,
  };
}
