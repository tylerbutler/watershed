import { componentModelDocs, foundationsDocs } from "./foundations.ts";
import { steps } from "./guide.ts";
import { runtimeDocs } from "./runtime.ts";
import { categories } from "./structures.ts";

export interface NavigationLink {
  label: string;
  href: string;
  footerLabel?: string;
  external?: boolean;
}

export interface NavigationSection extends NavigationLink {
  id: string;
  match: string;
  fullLabel?: string;
  footerTitle?: string;
  footerHubLabel?: string;
  links?: NavigationLink[];
}

export interface NavigationGroup {
  id: string;
  links: NavigationSection[];
}

const numberedLinks = (
  base: string,
  docs: readonly { slug: string; title: string }[],
): NavigationLink[] =>
  docs.map((doc, index) => ({
    label: `${String(index + 1).padStart(2, "0")} ${doc.title.split(" and ")[0]}`,
    footerLabel: doc.title,
    href: `${base}/${doc.slug}`,
  }));

export const navigationSections = {
  foundations: {
    id: "foundations",
    label: "Foundations",
    footerTitle: "Foundations",
    href: "/foundations",
    match: "/foundations",
    footerHubLabel: "Overview",
    links: numberedLinks("/foundations", foundationsDocs),
  },
  components: {
    id: "components",
    label: "Components",
    fullLabel: "Component model",
    footerTitle: "Component model",
    href: "/component-model",
    match: "/component-model",
    footerHubLabel: "Overview",
    links: numberedLinks("/component-model", componentModelDocs),
  },
  guide: {
    id: "guide",
    label: "Guide",
    fullLabel: "Build guide",
    footerTitle: "Build guide",
    href: "/guide",
    match: "/guide",
    footerHubLabel: "Overview",
    links: steps.map((step) => ({
      label: `${step.n} ${step.title}`,
      footerLabel: `${step.n} · ${step.title}`,
      href: `/guide/${step.slug}`,
    })),
  },
  atlas: {
    id: "atlas",
    label: "Atlas",
    fullLabel: "Field atlas",
    footerTitle: "Data structures",
    href: "/structures",
    match: "/structures",
    footerHubLabel: "Field atlas",
    links: categories.map((category) => ({
      label: category.name,
      href: `/structures/${category.slug}`,
    })),
  },
  runtime: {
    id: "runtime",
    label: "Runtime",
    footerTitle: "Runtime",
    href: "/runtime",
    match: "/runtime",
    footerHubLabel: "Behaviors",
    links: runtimeDocs.map((doc) => ({
      label: doc.title,
      href: `/runtime/${doc.slug}`,
    })),
  },
  models: {
    id: "models",
    label: "Models",
    href: "/models",
    match: "/models",
  },
  examples: {
    id: "examples",
    label: "Examples",
    href: "/examples",
    match: "/examples",
  },
  source: {
    id: "source",
    label: "Source",
    href: "https://github.com/tylerbutler/watershed",
    match: "",
    external: true,
  },
} as const satisfies Record<string, NavigationSection>;

export const topNavigationGroups: NavigationGroup[] = [
  {
    id: "model",
    links: [navigationSections.foundations, navigationSections.components],
  },
  { id: "guide", links: [navigationSections.guide] },
  { id: "atlas", links: [navigationSections.atlas] },
  { id: "runtime", links: [navigationSections.runtime] },
  { id: "models", links: [navigationSections.models] },
  { id: "examples", links: [navigationSections.examples] },
  { id: "source", links: [navigationSections.source] },
];

export const footerNavigationSections = [
  navigationSections.foundations,
  navigationSections.components,
  navigationSections.guide,
  navigationSections.atlas,
  navigationSections.runtime,
] as const;

const normalizePath = (path: string) =>
  path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;

export function contextualNavigation(path: string): {
  label: string;
  href: string;
  links: (NavigationLink & { current: boolean })[];
} | null {
  const normalizedPath = normalizePath(path);
  const sections: NavigationSection[] = Object.values(navigationSections);
  const section = sections.find(
    (candidate) =>
      candidate.links &&
      (normalizedPath === candidate.match ||
        normalizedPath.startsWith(`${candidate.match}/`)),
  );

  if (!section?.links) {
    return null;
  }

  return {
    label: section.fullLabel ?? section.label,
    href: section.href,
    links: [
      {
        label: "Overview",
        href: section.href,
        current: normalizedPath === section.href,
      },
      ...section.links.map((link) => ({
        ...link,
        current: normalizedPath === link.href,
      })),
    ],
  };
}
