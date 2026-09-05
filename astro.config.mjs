import { defineConfig } from "astro/config";
import { unified } from "@astrojs/markdown-remark";
import starlight from "@astrojs/starlight";
import starlightImageZoom from "starlight-image-zoom";
import { starlightBasePath } from "starlight-base-path";
import mermaid from "astro-mermaid";

// Custom domain root: https://kinesis-s3-delivery-walkthrough.johna.kiwi
const site = "https://kinesis-s3-delivery-walkthrough.johna.kiwi";
const base = "/";

export default defineConfig({
  site,
  base,
  // starlight-image-zoom and astro-mermaid need the remark/rehype pipeline.
  markdown: {
    processor: unified(),
  },
  integrations: [
    mermaid(),
    starlight({
      title: "Kinesis S3 Delivery Walkthrough",
      favicon: "/favicon.svg",
      description:
        "Guided CLI walkthrough for Amazon Kinesis Data Streams delivery to general purpose Amazon S3 buckets.",
      customCss: [
        "./src/styles/patina-tokens.css",
        "./src/styles/splash-overrides.css",
      ],
      components: {
        ThemeSelect: "./src/components/ThemeSelect.astro",
        Head: "./src/components/Head.astro",
      },
      head: [
        {
          tag: "meta",
          attrs: {
            property: "og:image",
            content: `${site}${base}og-image.png`,
          },
        },
        {
          tag: "meta",
          attrs: {
            property: "og:image:alt",
            content:
              "Kinesis S3 Delivery Walkthrough — stream, channel, S3, teardown",
          },
        },
        {
          tag: "meta",
          attrs: {
            name: "twitter:image",
            content: `${site}${base}og-image.png`,
          },
        },
      ],
      plugins: [starlightBasePath(), starlightImageZoom()],
      social: [
        {
          icon: "github",
          label: "Source Repository",
          href: "https://github.com/jajera/kinesis-s3-delivery-walkthrough",
        },
      ],
      editLink: {
        baseUrl:
          "https://github.com/jajera/kinesis-s3-delivery-walkthrough/edit/main/",
      },
      lastUpdated: true,
      pagination: true,
      sidebar: [
        { label: "Home", link: "/" },
        { label: "Install tooling", slug: "install-tooling" },
        { label: "Prerequisites", slug: "prerequisites" },
        {
          label: "Walkthrough",
          items: [
            { label: "CLI overview", slug: "cli" },
            { label: "Create the stream", slug: "cli/setup/stream" },
            { label: "Create the bucket", slug: "cli/setup/bucket" },
            {
              label: "IAM and delivery",
              slug: "cli/setup/iam-and-delivery",
            },
            { label: "Produce records", slug: "cli/produce" },
            { label: "Verify in S3", slug: "cli/verify-s3" },
            { label: "Visualize", slug: "cli/visualize" },
            { label: "Tear down", slug: "cli/teardown" },
          ],
        },
        {
          label: "Reference",
          items: [
            { label: "Commands", slug: "reference/commands" },
            { label: "Costs and limits", slug: "reference/costs-and-limits" },
            { label: "Troubleshooting", slug: "reference/troubleshooting" },
            {
              label: "Cleanup checklist",
              slug: "reference/cleanup-checklist",
            },
          ],
        },
      ],
    }),
  ],
});
