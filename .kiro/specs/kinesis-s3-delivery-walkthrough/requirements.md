# Requirements Document

## Introduction

This feature delivers a published walkthrough site for `jajera/kinesis-s3-delivery-walkthrough`:
a guided AWS CLI lab that proves **Amazon Kinesis Data Streams delivery to general purpose Amazon
S3 buckets**, announced 29 Aug 2026.

The Repository contains documentation, a guided shell script, and CI configuration. It ships no
Terraform, CDK, or CloudFormation. The reader creates AWS resources by running the documented
commands themselves.

All AWS behavioural statements in this document were verified against the Amazon Kinesis Data
Streams developer guide (`data-delivery*` pages), the AWS CLI `kinesis create-channel` reference,
and the Kinesis Data Streams pricing and FAQ pages on **2026-09-03**. The full source list lives
in `.kiro/steering/aws-source-lock.md`.

### Confirmed Decisions

1. **Producer (default)**: EventBridge → Lambda `PutRecord` heartbeat (`demo.sh producer`),
   runtime **python3.14**, 128 MB, default schedule `rate(5 minutes)`. Always-on for the lab;
   torn down with `down`.
2. **Producer (optional burst)**: [`aws-samples/amazon-kinesis-replay`](https://github.com/aws-samples/amazon-kinesis-replay)
   replaying the default NYC TLC taxi dataset on the operator's machine. Leaves no AWS resources.
3. **Path**: guided AWS CLI wrapped by `scripts/demo.sh`. No IaC as the primary path.
4. **Region**: `ap-southeast-2`. `Kinesis+CreateChannel` reports `isAvailableIn` for that Region.
5. **Visualization**: presented as options. The lab is complete without choosing one.
6. **Capacity mode**: On-Demand, because delivery channels require it.
7. **Docs stack**: Astro Starlight.
8. **Build order**: author the complete walkthrough first; run it and capture evidence second.

## Glossary

- **Repository** — the Git repository `jajera/kinesis-s3-delivery-walkthrough`.
- **Docs_Site** — the Astro Starlight site built from `src/content/docs/`.
- **Demo_Script** — `scripts/demo.sh`, exposing `up`, `status`, `producer`, `replay`, `viz`, and
  `down`.
- **Delivery_Channel** — the Kinesis Data Streams resource created by `CreateChannel`, labelled
  **S3 general purpose delivery** in the console.
- **Service_Execution_Role** — the IAM role Kinesis Data Streams assumes to write to the
  destination bucket.
- **Heartbeat_Producer** — EventBridge schedule + Lambda that calls `PutRecord` on the lab stream.
- **Replay_Producer** — the optional `amazon-kinesis-replay` Java application.
- **Source_Lock** — `.kiro/steering/aws-source-lock.md`, the citation rules and verified facts.
- **Evidence_Pass** — the later phase that runs the lab, fixes it, and captures screenshots.
- **Reader** — an engineer following the published walkthrough.
- **Contributor** — a person changing files in the Repository.

## Requirements

### Requirement 1: Documentation and Script Only

**User Story:** As a Reader, I want the Repository to contain documentation and a lab script only,
so that cloning it never provisions anything by itself.

#### Acceptance Criteria

1. THE Repository SHALL restrict tracked content to documentation under `src/`, the Demo_Script
   under `scripts/`, agent configuration under `.kiro/`, CI configuration under `.github/`, and
   root-level project files.
2. THE Repository SHALL contain zero files with the extensions `.tf`, `.tf.json`, or `.tfvars`,
   and no `cdk.json` or CloudFormation template.
3. WHEN the Demo_Script runs without a subcommand, THE Demo_Script SHALL print usage and exit
   without calling any AWS API.

### Requirement 2: Prerequisites Are Stated Before Any Cost Is Incurred

**User Story:** As a Reader, I want to know the account, tooling, and cost implications up front,
so that I do not discover them halfway through.

#### Acceptance Criteria

1. THE Docs_Site SHALL state that the lab creates billable AWS resources and SHALL link
   <https://aws.amazon.com/kinesis/data-streams/pricing/> rather than hardcoding a rate.
2. THE Docs_Site SHALL state the AWS CLI version used to verify the lab, the Lambda runtime of the
   Heartbeat_Producer, and the Java requirement of the optional Replay_Producer.
3. THE Docs_Site SHALL state that the Delivery_Channel requires a stream in On-Demand Standard or
   On-Demand Advantage capacity mode, and that provisioned mode is not supported.
4. THE Docs_Site SHALL state that the destination bucket must be in the same Region as the stream.

### Requirement 3: Setup Path

**User Story:** As a Reader, I want each resource created in dependency order with a copy-paste
command, so that the delivery channel succeeds on the first attempt.

#### Acceptance Criteria

1. THE Docs_Site SHALL order setup as stream, then destination bucket, then Service_Execution_Role
   and Delivery_Channel.
2. THE Docs_Site SHALL show the Service_Execution_Role trust policy with principal
   `kinesis.amazonaws.com` and both the `aws:SourceAccount` and `aws:SourceArn` conditions from
   the AWS IAM documentation for data delivery.
3. THE Docs_Site SHALL state that the calling principal needs `kinesis:CreateChannel`,
   `kinesis:AssociateStreamsWithChannel`, and `iam:PassRole` on the Service_Execution_Role.
4. THE Docs_Site SHALL create the Delivery_Channel with `aws kinesis create-channel`, specifying
   `--service-execution-role-arn`, `--stream-configuration-list`, and
   `--s3-destination-configuration`.
5. THE Docs_Site SHALL state that `CreateChannel` is asynchronous and SHALL show
   `aws kinesis describe-channel` polling until the state is `ACTIVE`.
6. WHERE the Docs_Site shows an output key template with GZIP or ZSTD compression, THE Docs_Site
   SHALL end that template with an extension placeholder.
7. THE Docs_Site SHALL state that a dead-letter queue is optional for general purpose S3 delivery
   and defaults to the destination bucket with an error prefix.

### Requirement 4: Produce and Ordering

**User Story:** As a Reader, I want the producer started at the right moment, so that the records
I publish are actually delivered.

#### Acceptance Criteria

1. THE Docs_Site SHALL instruct the Reader to start the Heartbeat_Producer (and any optional
   Replay_Producer) only after the Delivery_Channel reaches `ACTIVE`.
2. THE Docs_Site SHALL state that records written to the stream before the Delivery_Channel became
   `ACTIVE` are not delivered, because delivery does not backfill.
3. THE Docs_Site SHALL present the Heartbeat_Producer as the default path via `demo.sh producer`
   (EventBridge → Lambda `PutRecord`, python3.14).
4. WHERE the Docs_Site documents the optional Replay_Producer, THE Docs_Site SHALL invoke it with
   `-streamArn`, SHALL describe `-speedup` as the way to compress replay time, and SHALL state that
   Ctrl+C stops it and leaves no AWS resources behind.
5. THE Docs_Site SHALL state that delivery does not consume the stream's read throughput and does
   not affect other consumers.

### Requirement 5: Verification

**User Story:** As a Reader, I want to confirm delivery worked and understand the wait, so that I
do not conclude the lab failed while it is still buffering.

#### Acceptance Criteria

1. THE Docs_Site SHALL state that `DataFreshnessInSeconds` accepts 300 to 900 seconds and defaults
   to 300, and SHALL tell the Reader to wait at least the configured window before expecting
   objects.
2. THE Docs_Site SHALL show listing delivered objects with `aws s3 ls` and reading one record.
3. THE Docs_Site SHALL name the CloudWatch namespace `AWS/Kinesis`, the `DeliveryToS3.` metric
   prefix, and the `ChannelName`, `ChannelId`, and `StreamName` dimensions.
4. THE Docs_Site SHALL identify `DeliveryToS3.FailedRecordCount` as the primary error signal and
   `DeliveryToS3.DataFreshness` as the lag signal.

### Requirement 6: Visualization Stays Open

**User Story:** As a Reader, I want to choose my own visualization tool, so that the lab does not
force a stack on me.

#### Acceptance Criteria

1. THE Docs_Site SHALL present visualization as an optional step (branded HTML report via
   `demo.sh viz`, plus console deep links).
2. THE Docs_Site SHALL define lab completion as delivered objects verified in Amazon S3, without
   requiring a visualization tool.
3. WHERE the Docs_Site shows a report or query example, THE Docs_Site SHALL mark it optional.

### Requirement 7: Teardown Leaves Nothing Behind

**User Story:** As a Reader, I want a single reliable teardown, so that the lab stops costing money
the moment I am finished.

#### Acceptance Criteria

1. THE Docs_Site SHALL state that an active Delivery_Channel continues to process records and
   incur delivery charges until it is deleted.
2. THE Docs_Site SHALL order teardown as Heartbeat_Producer (rule, Lambda, role), then
   Delivery_Channel, then destination bucket contents and bucket, then stream, then
   Service_Execution_Role and its policies.
3. WHEN the Demo_Script runs `down`, THE Demo_Script SHALL require an explicit confirmation before
   deleting anything.
4. WHEN the Demo_Script runs `down`, THE Demo_Script SHALL empty the destination bucket before
   deleting it.
5. THE Docs_Site SHALL provide a cleanup checklist naming every resource type the lab creates.
6. THE Demo_Script SHALL NOT delete any resource whose name lacks the lab prefix.

### Requirement 8: Source Grounding

**User Story:** As a Reader, I want every AWS claim traceable, so that I can trust a walkthrough
about a capability that is only weeks old.

#### Acceptance Criteria

1. THE Docs_Site SHALL end every page that makes an AWS behavioural claim with a References
   section linking the AWS documentation page stating that behaviour.
2. THE Docs_Site SHALL record the date on which its AWS statements were last verified.
3. WHERE a behaviour has not been observed in an AWS account, THE Docs_Site SHALL mark it as
   unverified rather than asserting it.
4. THE Repository SHALL keep the Source_Lock current, and a Contributor who discovers a
   contradiction SHALL update both the Source_Lock and the affected page.

### Requirement 9: Agent Guard Rails

**User Story:** As a Contributor using an AI agent, I want mutations blocked by default, so that
authoring the lab never creates AWS resources by accident.

#### Acceptance Criteria

1. THE Repository SHALL provide a blocking `PreToolUse` hook that rejects mutating AWS CLI calls
   from shell tools and returns a non-zero exit status of 2.
2. THE hook SHALL allow read-only AWS CLI calls, specifically `describe-*`, `list-*`, `get-*`,
   `aws s3 ls`, and `aws sts get-caller-identity`.
3. THE hook SHALL allow mutations WHEN the environment variable `KDS_LAB_ALLOW_AWS` equals `1`.
4. THE hook SHALL NOT block writing documentation that contains example AWS commands.
5. THE Repository SHALL configure the `aws-api` MCP server as disabled by default.
6. THE Repository SHALL provide quality gates that fail the build WHEN a fenced code block
   contains an account identifier outside the documented placeholder set, WHEN a page uses an
   aside type outside `tip`, `note`, `caution`, and `danger`, WHEN a published page under `cli/`
   or `reference/` has no References section, or WHEN a page cites an AWS URL that is absent from
   the Source_Lock.
7. THE quality gates SHALL run on every pull request and SHALL be runnable offline via
   `SKIP_LINK_CHECK=1`.

### Requirement 10: Build Order and Evidence

**User Story:** As a Contributor, I want authoring and validation separated, so that the site is
complete before anyone spends money running it.

#### Acceptance Criteria

1. THE Repository SHALL treat content completion and the Evidence_Pass as distinct phases.
2. WHERE a page needs a screenshot or a real diagram, THE Docs_Site SHALL carry a visible evidence
   marker until the Evidence_Pass replaces it.
3. THE Docs_Site SHALL use text diagrams during authoring and replace them with rendered diagrams
   during the Evidence_Pass.
4. WHEN the Evidence_Pass completes, THE Repository SHALL contain no unresolved `TBD` entries in
   the Source_Lock.
