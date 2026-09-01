import React, { startTransition, useDeferredValue, useEffect, useId, useMemo, useState } from 'react';
import {
  Avatar,
  Badge,
  Body1,
  Button,
  Caption1,
  Card,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Dropdown,
  Field,
  FluentProvider,
  Input,
  makeStyles,
  MessageBar,
  MessageBarBody,
  Option,
  shorthands,
  Spinner,
  Subtitle1,
  Table,
  TableBody,
  TableCell,
  TableCellLayout,
  TableHeader,
  TableHeaderCell,
  TableRow,
  Tab,
  TabList,
  Title1,
  tokens,
  webDarkTheme,
  webLightTheme,
} from '@fluentui/react-components';
import {
  ArrowClockwise20Regular,
  ChevronLeft20Regular,
  ChevronRight20Regular,
  DataHistogram24Regular,
  Dismiss24Regular,
  DocumentDatabase20Regular,
  Globe20Regular,
  History24Regular,
  PlayCircle24Regular,
  WeatherMoon20Regular,
  WeatherSunny20Regular,
} from '@fluentui/react-icons';

const emptySummary = {
  total: 0,
  matching: 0,
  gaps: 0,
  identityGaps: 0,
  families: 0,
};

const hiddenCapabilityKeys = new Set(['provider_surface_area', 'metadata_uniques', 'zone_support_posture']);

const pageSize = 12;
const detailTablePageSize = 20;
const emptyPricingFilters = { productName: '', skuName: '', meterName: '' };

const STATUS_SURFACE_LIGHT = {
  FULL_MATCH: { borderColor: '#107c41', backgroundColor: '#f1fbf5', accentColor: '#107c41' },
  SOURCE_EXTENDED: { borderColor: '#b76e00', backgroundColor: '#fff7e6', accentColor: '#8a5a00' },
  TARGET_EXTENDED: { borderColor: '#0f6cbd', backgroundColor: '#eef6fc', accentColor: '#0f6cbd' },
  AVAILABLE_NO_SKUS: { borderColor: '#5c2e91', backgroundColor: '#f6f0ff', accentColor: '#5c2e91' },
  AVAILABLE: { borderColor: '#0f6cbd', backgroundColor: '#eef6fc', accentColor: '#0f6cbd' },
  CONDITIONAL: { borderColor: '#b76e00', backgroundColor: '#fff7e6', accentColor: '#8a5a00' },
  UNAVAILABLE: { borderColor: '#c4314b', backgroundColor: '#fff1f3', accentColor: '#c4314b' },
};

const STATUS_SURFACE_DARK = {
  FULL_MATCH: { borderColor: '#3fb950', backgroundColor: 'rgba(25, 63, 38, 0.62)', accentColor: '#3fb950' },
  SOURCE_EXTENDED: { borderColor: '#d29922', backgroundColor: 'rgba(88, 57, 18, 0.58)', accentColor: '#d29922' },
  TARGET_EXTENDED: { borderColor: '#58a6ff', backgroundColor: 'rgba(22, 56, 96, 0.58)', accentColor: '#58a6ff' },
  AVAILABLE_NO_SKUS: { borderColor: '#bc8cff', backgroundColor: 'rgba(64, 39, 89, 0.58)', accentColor: '#bc8cff' },
  AVAILABLE: { borderColor: '#58a6ff', backgroundColor: 'rgba(22, 56, 96, 0.58)', accentColor: '#58a6ff' },
  CONDITIONAL: { borderColor: '#d29922', backgroundColor: 'rgba(88, 57, 18, 0.58)', accentColor: '#d29922' },
  UNAVAILABLE: { borderColor: '#ff7b72', backgroundColor: 'rgba(104, 32, 48, 0.58)', accentColor: '#ff7b72' },
};

const useStyles = makeStyles({
  shell: {
    minHeight: '100vh',
    background: 'linear-gradient(180deg, var(--app-shell-start) 0%, var(--app-shell-end) 100%)',
    color: tokens.colorNeutralForeground1,
  },
  frame: {
    maxWidth: '1480px',
    marginLeft: 'auto',
    marginRight: 'auto',
    paddingTop: '16px',
    paddingRight: '24px',
    paddingBottom: '28px',
    paddingLeft: '24px',
    display: 'grid',
    gap: '14px',
  },
  hero: {
    display: 'grid',
    gridTemplateColumns: '1fr',
    gap: '12px',
    alignItems: 'start',
  },
  heroCopy: {
    display: 'grid',
    gap: '10px',
    alignContent: 'start',
  },
  eyebrow: {
    color: tokens.colorBrandForeground1,
    textTransform: 'uppercase',
    letterSpacing: '0.12em',
    fontSize: tokens.fontSizeBase200,
    fontWeight: tokens.fontWeightSemibold,
  },
  heroTitle: {
    margin: 0,
    maxWidth: '780px',
    color: tokens.colorNeutralForeground1,
    fontSize: 'clamp(2.15rem, 3.8vw, 3.8rem)',
    lineHeight: 0.96,
    letterSpacing: '-0.04em',
  },
  heroText: {
    maxWidth: '640px',
    color: tokens.colorNeutralForeground2,
  },
  heroActions: {
    display: 'flex',
    gap: '12px',
    alignItems: 'center',
    flexWrap: 'wrap',
    marginTop: '6px',
  },
  heroStatusStrip: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    flexWrap: 'wrap',
    minHeight: '32px',
  },
  heroStatusText: {
    color: tokens.colorNeutralForeground2,
  },
  heroStatusBadges: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    flexWrap: 'wrap',
  },
  heroCards: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: '12px',
    '@media (max-width: 1400px)': {
      gridTemplateColumns: '1fr',
    },
  },
  statusCard: {
    ...shorthands.padding('16px'),
    rowGap: '8px',
    display: 'grid',
    alignContent: 'start',
    minHeight: '96px',
    backgroundColor: 'var(--app-card-bg)',
    boxShadow: 'var(--app-soft-shadow)',
  },
  personaRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '14px',
    minWidth: 0,
  },
  personaDetails: {
    display: 'grid',
    gap: '2px',
    minWidth: 0,
  },
  truncateText: {
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  shellLayout: {
    display: 'grid',
    gridTemplateColumns: '260px minmax(0, 1fr)',
    gap: '20px',
    alignItems: 'start',
    '@media (max-width: 1100px)': {
      gridTemplateColumns: '1fr',
    },
  },
  navCard: {
    ...shorthands.padding('16px'),
    position: 'sticky',
    top: '20px',
    display: 'grid',
    gap: '12px',
    backgroundColor: 'var(--app-card-bg)',
    boxShadow: 'var(--app-soft-shadow)',
    '@media (max-width: 1100px)': {
      position: 'static',
    },
  },
  navTabs: {
    display: 'grid',
    gap: '8px',
  },
  navTabList: {
    display: 'grid',
    gap: '8px',
  },
  navHint: {
    color: tokens.colorNeutralForeground3,
  },
  contentColumn: {
    display: 'grid',
    gap: '14px',
  },
  summaryGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(4, minmax(0, 1fr))',
    gap: '10px',
    '@media (max-width: 1100px)': {
      gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    },
    '@media (max-width: 720px)': {
      gridTemplateColumns: '1fr',
    },
  },
  summaryCard: {
    ...shorthands.padding('14px'),
    display: 'grid',
    gap: '4px',
    boxShadow: 'var(--app-soft-shadow)',
  },
  summaryValue: {
    fontSize: tokens.fontSizeHero800,
    lineHeight: tokens.lineHeightHero800,
    fontWeight: tokens.fontWeightSemibold,
    fontVariantNumeric: 'tabular-nums',
    letterSpacing: '-0.02em',
  },
  summaryValueCompact: {
    fontSize: tokens.fontSizeBase400,
    lineHeight: tokens.lineHeightBase400,
    fontWeight: tokens.fontWeightSemibold,
    fontVariantNumeric: 'tabular-nums',
  },
  sectionCard: {
    ...shorthands.padding('16px'),
    display: 'grid',
    gap: '12px',
    backgroundColor: 'var(--app-card-bg)',
    boxShadow: 'var(--app-soft-shadow)',
  },
  sectionHeader: {
    display: 'flex',
    alignItems: 'start',
    justifyContent: 'space-between',
    gap: '12px',
    flexWrap: 'wrap',
  },
  sectionMeta: {
    display: 'grid',
    gap: '4px',
  },
  formGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: '16px',
    '@media (max-width: 720px)': {
      gridTemplateColumns: '1fr',
    },
  },
  wideField: {
    gridColumn: '1 / -1',
  },
  actionRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    flexWrap: 'wrap',
  },
  splitLayout: {
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1.3fr) minmax(300px, 0.7fr)',
    gap: '14px',
    '@media (max-width: 1100px)': {
      gridTemplateColumns: '1fr',
    },
  },
  stack: {
    display: 'grid',
    gap: '10px',
  },
  primaryOverviewCard: {
    gap: '14px',
  },
  overviewInset: {
    backgroundColor: 'var(--app-card-subtle-bg)',
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('12px', '14px'),
    display: 'grid',
    gap: '4px',
  },
  overviewList: {
    margin: 0,
    paddingLeft: '18px',
    display: 'grid',
    gap: '8px',
    color: tokens.colorNeutralForeground2,
  },
  overviewKeyGrid: {
    display: 'grid',
    gap: '10px',
  },
  overviewKeyItem: {
    display: 'grid',
    gap: '2px',
    backgroundColor: 'var(--app-card-subtle-bg)',
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('10px', '12px'),
  },
  runList: {
    display: 'grid',
    gap: '12px',
    maxHeight: '640px',
    overflowY: 'auto',
  },
  runButton: {
    width: '100%',
    display: 'grid',
    gridTemplateColumns: '4px 1fr',
    gap: '0',
    textAlign: 'left',
    color: tokens.colorNeutralForeground1,
    backgroundColor: 'var(--app-run-bg)',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusXLarge),
    overflow: 'hidden',
    boxShadow: tokens.shadow4,
    cursor: 'pointer',
    transitionDuration: tokens.durationNormal,
    transitionProperty: 'transform, border-color, box-shadow',
    transitionTimingFunction: tokens.curveEasyEase,
    ':hover': {
      transform: 'translateY(-1px)',
      borderColor: tokens.colorBrandStroke1,
      boxShadow: tokens.shadow8,
    },
  },
  runButtonAccent: {
    ...shorthands.borderRadius('3px', '0', '0', '3px'),
    height: '100%',
  },
  runButtonContent: {
    display: 'grid',
    gap: '8px',
    ...shorthands.padding('14px'),
  },
  runButtonSelected: {
    borderColor: tokens.colorBrandStroke1,
    backgroundColor: 'var(--app-run-selected-bg)',
    color: tokens.colorNeutralForeground1,
    boxShadow: tokens.shadow8,
  },
  runMeta: {
    color: tokens.colorNeutralForeground3,
  },
  toolbar: {
    display: 'grid',
    gridTemplateColumns: 'minmax(220px, 1.1fr) repeat(2, minmax(180px, 0.7fr)) auto',
    gap: '12px',
    alignItems: 'end',
    '@media (max-width: 1100px)': {
      gridTemplateColumns: '1fr 1fr',
    },
    '@media (max-width: 720px)': {
      gridTemplateColumns: '1fr',
    },
  },
  toolbarActions: {
    display: 'flex',
    justifyContent: 'flex-end',
    gap: '8px',
    flexWrap: 'wrap',
    '@media (max-width: 1100px)': {
      justifyContent: 'flex-start',
    },
  },
  triageGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(4, minmax(0, 1fr))',
    gap: '10px',
    '@media (max-width: 1100px)': {
      gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    },
    '@media (max-width: 720px)': {
      gridTemplateColumns: '1fr',
    },
  },
  triageCard: {
    display: 'grid',
    gap: '8px',
    backgroundColor: 'var(--app-card-subtle-bg)',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('12px', '14px'),
  },
  triageCardActive: {
    borderColor: tokens.colorBrandStroke1,
    boxShadow: tokens.shadow4,
  },
  triageCount: {
    fontSize: tokens.fontSizeHero700,
    lineHeight: tokens.lineHeightHero700,
    fontWeight: tokens.fontWeightSemibold,
  },
  triageDescription: {
    color: tokens.colorNeutralForeground2,
  },
  tableWrap: {
    overflowX: 'auto',
  },
  table: {
    minWidth: '940px',
  },
  wrapText: {
    whiteSpace: 'normal',
    overflowWrap: 'anywhere',
    lineHeight: '1.4',
  },
  providerText: {
    whiteSpace: 'normal',
    overflowWrap: 'anywhere',
    color: tokens.colorNeutralForeground2,
  },
  familyText: {
    whiteSpace: 'normal',
    overflowWrap: 'anywhere',
  },
  runHeadline: {
    display: 'grid',
    gap: '4px',
  },
  runSubhead: {
    color: tokens.colorNeutralForeground3,
  },
  resultCardList: {
    display: 'grid',
    gap: '12px',
  },
  resultDetails: {
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusXLarge),
    backgroundColor: 'var(--app-card-bg)',
    overflow: 'hidden',
    boxShadow: 'var(--app-soft-shadow)',
    '&[open] > summary': {
      borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    },
  },
  resultSummaryLead: {
    color: tokens.colorNeutralForeground2,
  },
  resultSummary: {
    listStyle: 'none',
    cursor: 'pointer',
    ...shorthands.padding('14px', '16px'),
    display: 'grid',
    gap: '10px',
    background: 'linear-gradient(180deg, var(--app-card-header-bg) 0%, transparent 100%)',
    '::-webkit-details-marker': {
      display: 'none',
    },
  },
  resultSummaryGrid: {
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) auto',
    gap: '12px',
    alignItems: 'start',
    '@media (max-width: 720px)': {
      gridTemplateColumns: '1fr',
    },
  },
  resultSummaryMeta: {
    display: 'grid',
    gap: '6px',
  },
  resultTagRow: {
    display: 'flex',
    gap: '8px',
    flexWrap: 'wrap',
    alignItems: 'center',
  },
  resultMetaBadge: {
    maxWidth: '100%',
  },
  metricStrip: {
    display: 'flex',
    gap: '8px',
    flexWrap: 'wrap',
    alignItems: 'stretch',
  },
  metricCard: {
    backgroundColor: 'var(--app-card-subtle-bg)',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('10px', '12px'),
    display: 'grid',
    gap: '2px',
    minWidth: '140px',
    flex: '1 1 160px',
  },
  metricCardValue: {
    fontVariantNumeric: 'tabular-nums',
    letterSpacing: '-0.02em',
  },
  resultDetailsBody: {
    display: 'grid',
    gap: '14px',
    ...shorthands.padding('0', '16px', '16px'),
  },
  matrixTable: {
    display: 'grid',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    overflow: 'hidden',
  },
  matrixHeader: {
    display: 'grid',
    gridTemplateColumns: 'minmax(180px, 1.1fr) 120px 120px 100px minmax(280px, 1fr)',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    '@media (max-width: 1100px)': {
      gridTemplateColumns: 'minmax(180px, 1.1fr) 120px 120px 100px',
    },
    '@media (max-width: 800px)': {
      display: 'none',
    },
  },
  matrixHeaderCell: {
    backgroundColor: 'var(--app-grid-header-bg)',
    ...shorthands.padding('10px', '12px'),
    fontWeight: tokens.fontWeightSemibold,
    color: tokens.colorNeutralForeground2,
  },
  matrixRow: {
    display: 'grid',
    gridTemplateColumns: 'minmax(180px, 1.1fr) 120px 120px 100px minmax(280px, 1fr)',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    '@media (max-width: 1100px)': {
      gridTemplateColumns: 'minmax(180px, 1.1fr) 120px 120px 100px',
    },
    '@media (max-width: 800px)': {
      display: 'grid',
      gridTemplateColumns: '1fr',
    },
  },
  matrixCell: {
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.padding('10px', '12px'),
    display: 'grid',
    gap: '4px',
  },
  matrixCapabilityCell: {
    backgroundColor: 'var(--app-card-subtle-bg)',
  },
  matrixNoteCell: {
    backgroundColor: 'var(--app-card-subtle-bg)',
    color: tokens.colorNeutralForeground2,
    '@media (max-width: 1100px)': {
      display: 'none',
    },
    '@media (max-width: 800px)': {
      display: 'grid',
    },
  },
  capabilityMeta: {
    color: tokens.colorNeutralForeground3,
  },
  zoneStrip: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: '12px',
    '@media (max-width: 900px)': {
      gridTemplateColumns: '1fr',
    },
  },
  zoneCard: {
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('10px', '12px'),
    backgroundColor: 'var(--app-card-subtle-bg)',
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) auto',
    gap: '6px 8px',
    alignItems: 'center',
  },
  zoneCardLabel: {
    display: 'grid',
    gap: '2px',
  },
  zoneCardMeta: {
    color: tokens.colorNeutralForeground2,
  },
  zoneCardExtra: {
    gridColumn: '1 / -1',
    display: 'flex',
    gap: '6px',
    alignItems: 'center',
    flexWrap: 'wrap',
  },
  metadataBlock: {
    display: 'grid',
    gap: '10px',
  },
  identityGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
    gap: '10px',
    '@media (max-width: 960px)': {
      gridTemplateColumns: '1fr',
    },
  },
  identityCard: {
    backgroundColor: 'var(--app-card-subtle-bg)',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('12px', '14px'),
    display: 'grid',
    gap: '6px',
    alignContent: 'start',
  },
  identityBadgeRow: {
    display: 'flex',
    gap: '8px',
    flexWrap: 'wrap',
    alignItems: 'center',
  },
  expandedBlock: {
    display: 'grid',
    gap: '10px',
  },
  expandedDetails: {
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    backgroundColor: 'var(--app-card-subtle-bg)',
    overflow: 'hidden',
  },
  expandedSummary: {
    cursor: 'pointer',
    listStyle: 'none',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: '12px',
    ...shorthands.padding('12px', '14px'),
    fontWeight: tokens.fontWeightSemibold,
  },
  expandedSummaryMeta: {
    display: 'grid',
    gap: '2px',
  },
  expandedBody: {
    display: 'grid',
    gap: '10px',
    ...shorthands.padding('0', '14px', '14px'),
  },
  expandedNestedDetails: {
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusMedium),
    backgroundColor: 'var(--app-card-bg)',
    overflow: 'hidden',
  },
  expandedNestedSummary: {
    cursor: 'pointer',
    listStyle: 'none',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: '12px',
    ...shorthands.padding('10px', '12px'),
    color: tokens.colorNeutralForeground2,
  },
  expandedTable: {
    display: 'grid',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
  },
  expandedHeader: {
    display: 'grid',
    gridTemplateColumns: 'minmax(180px, 1fr) 160px 160px minmax(220px, 1fr) minmax(220px, 1fr)',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    '@media (max-width: 980px)': {
      display: 'none',
    },
  },
  expandedHeaderCell: {
    backgroundColor: 'var(--app-grid-header-bg)',
    ...shorthands.padding('10px', '12px'),
    fontWeight: tokens.fontWeightSemibold,
    color: tokens.colorNeutralForeground2,
  },
  expandedRow: {
    display: 'grid',
    gridTemplateColumns: 'minmax(180px, 1fr) 160px 160px minmax(220px, 1fr) minmax(220px, 1fr)',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    '@media (max-width: 980px)': {
      gridTemplateColumns: '1fr',
    },
  },
  expandedCell: {
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.padding('10px', '12px'),
    display: 'grid',
    gap: '4px',
  },
  pricingPanel: {
    display: 'grid',
    gap: '10px',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('12px', '14px'),
    backgroundColor: 'var(--app-card-subtle-bg)',
  },
  pricingPanelHeader: {
    display: 'flex',
    alignItems: 'start',
    justifyContent: 'space-between',
    gap: '12px',
    flexWrap: 'wrap',
  },
  pricingPanelMeta: {
    display: 'grid',
    gap: '4px',
  },
  pricingFilterBar: {
    display: 'grid',
    gap: '8px',
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('12px', '14px'),
  },
  pricingFilterHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: '10px',
    flexWrap: 'wrap',
  },
  pricingFilterMeta: {
    display: 'grid',
    gap: '2px',
  },
  pricingFilterGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
    gap: '10px',
    '& input, & button': {
      width: '100%',
      minWidth: 0,
    },
    '@media (max-width: 920px)': {
      gridTemplateColumns: '1fr',
    },
  },
  pricingTable: {
    display: 'grid',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    overflow: 'hidden',
  },
  pricingHeader: {
    display: 'grid',
    gridTemplateColumns: 'minmax(220px, 1.2fr) minmax(150px, 0.8fr) minmax(150px, 0.8fr) minmax(150px, 0.8fr)',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    '@media (max-width: 980px)': {
      display: 'none',
    },
  },
  pricingHeaderCell: {
    backgroundColor: 'var(--app-grid-header-bg)',
    ...shorthands.padding('10px', '12px'),
    fontWeight: tokens.fontWeightSemibold,
    color: tokens.colorNeutralForeground2,
  },
  pricingRow: {
    display: 'grid',
    gridTemplateColumns: 'minmax(220px, 1.2fr) minmax(150px, 0.8fr) minmax(150px, 0.8fr) minmax(150px, 0.8fr)',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    '@media (max-width: 980px)': {
      gridTemplateColumns: '1fr',
    },
  },
  pricingCell: {
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.padding('10px', '12px'),
    display: 'grid',
    gap: '4px',
  },
  pricingMeterCell: {
    backgroundColor: 'var(--app-card-subtle-bg)',
  },
  pricingValue: {
    display: 'grid',
    gap: '2px',
  },
  pricingPreviewCell: {
    display: 'grid',
    gap: '8px',
    alignContent: 'start',
    minWidth: 0,
    overflowWrap: 'anywhere',
  },
  pricingPreviewAction: {
    justifySelf: 'start',
    minWidth: 'unset',
  },
  pricingDialogSurface: {
    boxSizing: 'border-box',
    width: 'min(calc(100vw - 32px), 1280px)',
    maxWidth: 'none',
    height: 'min(88dvh, 900px)',
    maxHeight: 'calc(100dvh - 32px)',
    '--app-card-bg': tokens.colorNeutralBackground1,
    '--app-card-subtle-bg': tokens.colorNeutralBackground2,
    '--app-grid-header-bg': tokens.colorNeutralBackground3,
    '--app-grid-line': tokens.colorNeutralStroke2,
    backgroundColor: tokens.colorNeutralBackground1,
    color: tokens.colorNeutralForeground1,
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    boxShadow: tokens.shadow48,
    overflow: 'hidden',
    '@media (max-width: 600px)': {
      width: '100vw',
      height: '100dvh',
      maxHeight: '100dvh',
      ...shorthands.borderRadius(0),
      ...shorthands.border('0'),
    },
  },
  pricingDialogBody: {
    display: 'grid',
    gridTemplateRows: 'auto minmax(0, 1fr) auto',
    minHeight: 0,
    height: '100%',
    maxHeight: '100%',
  },
  pricingDialogTitle: {
    display: 'grid',
    gap: '6px',
    position: 'sticky',
    top: 0,
    zIndex: 2,
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.padding('16px', '18px', '12px', '18px'),
    ...shorthands.borderBottom('1px', 'solid', tokens.colorNeutralStroke2),
    '@media (max-width: 600px)': {
      ...shorthands.padding('12px', '12px', '10px', '12px'),
    },
  },
  pricingDialogTitleHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: '12px',
    flexWrap: 'wrap',
  },
  pricingDialogTitleText: {
    fontWeight: tokens.fontWeightSemibold,
    fontSize: tokens.fontSizeBase500,
    lineHeight: tokens.lineHeightBase500,
    overflowWrap: 'anywhere',
  },
  pricingDialogContext: {
    color: tokens.colorNeutralForeground2,
  },
  pricingDialogContent: {
    display: 'grid',
    gap: '12px',
    minHeight: 0,
    overflowY: 'auto',
    overflowX: 'hidden',
    ...shorthands.padding('0', '18px', '14px', '18px'),
    '@media (max-width: 600px)': {
      ...shorthands.padding('0', '12px', '12px', '12px'),
    },
  },
  pricingDialogSummary: {
    display: 'grid',
    gap: '6px',
    backgroundColor: 'var(--app-card-subtle-bg)',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('12px', '14px'),
  },
  pricingDialogSummaryEyebrow: {
    color: tokens.colorBrandForeground1,
    textTransform: 'uppercase',
    letterSpacing: '0.06em',
    fontSize: tokens.fontSizeBase200,
    fontWeight: tokens.fontWeightSemibold,
  },
  pricingDialogSummaryMetrics: {
    display: 'flex',
    gap: '8px',
    flexWrap: 'wrap',
    alignItems: 'center',
  },
  pricingDialogMetricBadge: {
    backgroundColor: tokens.colorBrandBackground2,
    color: tokens.colorBrandForeground1,
    ...shorthands.border('1px', 'solid', tokens.colorBrandStroke2),
  },
  pricingGroupList: {
    display: 'grid',
    gap: '10px',
  },
  pricingGroupCard: {
    display: 'grid',
    gap: '8px',
    backgroundColor: 'var(--app-card-subtle-bg)',
  },
  pricingGroupHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: '10px',
    flexWrap: 'wrap',
  },
  pricingGroupTable: {
    display: 'grid',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    ...shorthands.borderRadius(tokens.borderRadiusMedium),
    overflow: 'hidden',
  },
  pricingGroupTableHeader: {
    display: 'grid',
    gridTemplateColumns: 'minmax(220px, 1.2fr) minmax(150px, 0.8fr) minmax(150px, 0.8fr) minmax(170px, 0.9fr)',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    '@media (max-width: 860px)': {
      display: 'none',
    },
  },
  pricingGroupHeaderCell: {
    backgroundColor: 'var(--app-grid-header-bg)',
    ...shorthands.padding('10px', '12px'),
    fontWeight: tokens.fontWeightSemibold,
    color: tokens.colorNeutralForeground2,
  },
  pricingGroupRow: {
    display: 'grid',
    gridTemplateColumns: 'minmax(220px, 1.2fr) minmax(150px, 0.8fr) minmax(150px, 0.8fr) minmax(170px, 0.9fr)',
    gap: '1px',
    backgroundColor: 'var(--app-grid-line)',
    '@media (max-width: 860px)': {
      gridTemplateColumns: '1fr',
    },
  },
  pricingGroupCell: {
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.padding('12px', '14px'),
    display: 'grid',
    gap: '4px',
  },
  pricingGroupNameCell: {
    backgroundColor: 'var(--app-card-subtle-bg)',
  },
  pricingMatrixTable: {
    display: 'grid',
    gap: '10px',
    minWidth: 0,
  },
  pricingMatrixViewport: {
    minHeight: 0,
    overflow: 'visible',
    maxWidth: '100%',
  },
  pricingMatrixRow: {
    display: 'grid',
    gridTemplateRows: 'auto auto',
    gap: '1px',
    minWidth: 0,
    backgroundColor: 'var(--app-grid-line)',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    overflow: 'hidden',
  },
  pricingMatrixOffers: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 250px), 1fr))',
    gap: '1px',
    minWidth: 0,
    backgroundColor: 'var(--app-grid-line)',
  },
  pricingMatrixCell: {
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.padding('10px', '12px'),
    display: 'grid',
    gap: '6px',
    minWidth: '0',
    alignContent: 'start',
  },
  pricingNestedTable: {
    display: 'grid',
    gap: '2px',
    backgroundColor: 'var(--app-grid-line)',
    ...shorthands.borderRadius(tokens.borderRadiusMedium),
    overflow: 'hidden',
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
  },
  pricingNestedHeader: {
    display: 'grid',
    gridTemplateColumns: 'minmax(64px, 0.8fr) minmax(0, 1fr) minmax(0, 1.1fr)',
    gap: '2px',
    backgroundColor: 'var(--app-grid-line)',
  },
  pricingNestedRow: {
    display: 'grid',
    gridTemplateColumns: 'minmax(64px, 0.8fr) minmax(0, 1fr) minmax(0, 1.1fr)',
    gap: '2px',
    backgroundColor: 'var(--app-grid-line)',
  },
  pricingNestedHeaderCell: {
    backgroundColor: 'var(--app-grid-header-bg)',
    ...shorthands.padding('8px', '10px'),
    fontWeight: tokens.fontWeightSemibold,
    color: tokens.colorNeutralForeground2,
    fontSize: tokens.fontSizeBase100,
    overflowWrap: 'anywhere',
  },
  pricingNestedCell: {
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.padding('8px', '10px'),
    display: 'grid',
    gap: '1px',
    alignContent: 'start',
    minWidth: 0,
    overflowWrap: 'anywhere',
  },
  pricingNestedDeltaLabel: {
    fontWeight: tokens.fontWeightSemibold,
    lineHeight: '1.2',
    overflowWrap: 'anywhere',
  },
  pricingNestedDeltaDetail: {
    color: tokens.colorNeutralForeground2,
    fontSize: tokens.fontSizeBase100,
    lineHeight: '1.2',
    overflowWrap: 'anywhere',
  },
  pricingNestedRegionCell: {
    backgroundColor: 'var(--app-card-subtle-bg)',
    fontWeight: tokens.fontWeightSemibold,
  },
  pricingMatrixSkuCell: {
    backgroundColor: 'var(--app-card-subtle-bg)',
    alignSelf: 'stretch',
    minWidth: 0,
    ...shorthands.borderBottom('1px', 'solid', tokens.colorNeutralStroke2),
  },
  pricingMatrixSkuStack: {
    display: 'grid',
    gap: '2px',
    alignContent: 'start',
  },
  pricingMatrixSkuLabel: {
    color: tokens.colorNeutralForeground2,
    textTransform: 'uppercase',
    letterSpacing: '0.05em',
    fontSize: tokens.fontSizeBase100,
    fontWeight: tokens.fontWeightSemibold,
  },
  pricingMatrixSkuValue: {
    fontSize: tokens.fontSizeBase400,
    lineHeight: tokens.lineHeightBase400,
    fontWeight: tokens.fontWeightSemibold,
    overflowWrap: 'anywhere',
    wordBreak: 'break-word',
  },
  pricingMatrixModelTitle: {
    color: tokens.colorNeutralForeground2,
    fontWeight: tokens.fontWeightSemibold,
    fontSize: tokens.fontSizeBase200,
    lineHeight: tokens.lineHeightBase200,
    overflowWrap: 'anywhere',
  },
  pricingMatrixUnavailable: {
    color: tokens.colorNeutralForeground3,
  },
  pricingDialogActions: {
    position: 'sticky',
    bottom: 0,
    zIndex: 2,
    backgroundColor: 'var(--app-card-bg)',
    ...shorthands.borderTop('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.padding('10px', '18px', '16px', '18px'),
    '@media (max-width: 600px)': {
      ...shorthands.padding('10px', '12px', 'max(10px, env(safe-area-inset-bottom))', '12px'),
    },
  },
  pricingDeltaPositive: {
    color: '#c4314b',
    fontWeight: tokens.fontWeightSemibold,
    display: 'block',
  },
  pricingDeltaNegative: {
    color: '#107c41',
    fontWeight: tokens.fontWeightSemibold,
    display: 'block',
  },
  pricingDeltaNeutral: {
    color: tokens.colorNeutralForeground2,
    fontWeight: tokens.fontWeightSemibold,
    display: 'block',
  },
  expandedNameCell: {
    backgroundColor: 'var(--app-card-subtle-bg)',
  },
  expandedNoteCell: {
    color: tokens.colorNeutralForeground2,
  },
  metadataTable: {
    minWidth: '720px',
  },
  metadataName: {
    display: 'grid',
    gap: '2px',
  },
  availabilityGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: '12px',
    '@media (max-width: 900px)': {
      gridTemplateColumns: '1fr',
    },
  },
  availabilityPanel: {
    ...shorthands.border('1px', 'solid', tokens.colorNeutralStroke2),
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
    ...shorthands.padding('14px'),
    backgroundColor: 'var(--app-card-subtle-bg)',
    display: 'grid',
    gap: '8px',
  },
  detailDataTable: {
    minWidth: '880px',
  },
  detailCellStack: {
    display: 'grid',
    gap: '6px',
    alignContent: 'start',
    minWidth: '170px',
  },
  detailValueStrong: {
    fontWeight: tokens.fontWeightSemibold,
    display: 'block',
  },
  detailValueSubtle: {
    color: tokens.colorNeutralForeground2,
    display: 'block',
    lineHeight: '1.35',
    overflowWrap: 'anywhere',
    whiteSpace: 'normal',
  },
  detailValueMono: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase200,
    color: tokens.colorNeutralForeground3,
    display: 'block',
    lineHeight: '1.35',
    overflowWrap: 'anywhere',
    whiteSpace: 'normal',
  },
  detailSection: {
    display: 'grid',
    gap: '8px',
  },
  detailList: {
    margin: 0,
    paddingLeft: '18px',
    display: 'grid',
    gap: '6px',
  },
  detailItem: {
    color: tokens.colorNeutralForeground2,
  },
  monoText: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase200,
    color: tokens.colorNeutralForeground3,
  },
  pager: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: '12px',
    flexWrap: 'wrap',
  },
  pagerActions: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  emptyBlock: {
    ...shorthands.padding('20px'),
    color: tokens.colorNeutralForeground3,
    backgroundColor: 'var(--app-card-subtle-bg)',
    ...shorthands.borderRadius(tokens.borderRadiusLarge),
  },
});

function formatRunLabel(run) {
  return `${formatModeLabel(run.comparison_mode)} | ${run.source_region || 'source'} -> ${run.target_region || 'target'}`;
}

function formatRunMeta(run) {
  const details = [`${run.record_count || 0} records`, formatTimestamp(run.completed_at || run.started_at)].filter(Boolean);
  return details.join(' • ');
}

function formatModeLabel(mode) {
  const normalized = `${mode || ''}`.toLowerCase();
  if (normalized === 'regional') {
    return 'Regional';
  }
  if (normalized === 'inventory') {
    return 'Inventory';
  }
  return normalized ? normalized.charAt(0).toUpperCase() + normalized.slice(1) : 'Comparison';
}

function modeSupportText(mode) {
  const normalized = `${mode || ''}`.trim().toLowerCase();
  if (normalized === 'inventory') {
    return 'Start with the services already in your environment, then compare how well that footprint carries across regions.';
  }
  if (normalized === 'regional') {
    return 'Compare broad regional coverage without requiring an existing inventory first.';
  }
  return 'Choose a scope, select two regions, and compare service coverage side by side.';
}

function formatFamilyLabel(family) {
  const normalized = `${family || ''}`.trim();
  if (!normalized) {
    return 'Uncategorized';
  }
  const lower = normalized.toLowerCase();
  const aliases = {
    app: 'Application platform',
    'app-services': 'Application Platform',
    cache: 'Cache',
    compute: 'Compute',
    containers: 'Containers',
    databases: 'Databases',
    eventhub: 'Messaging',
    integration: 'Integration',
    machinelearningservices: 'AI',
    messaging: 'Messaging',
    monitoring: 'Monitoring',
    networking: 'Networking',
    storage: 'Storage',
  };
  if (aliases[lower]) {
    return aliases[lower];
  }
  return normalized
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[._-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (match) => match.toUpperCase());
}

function capabilityBadgeColor(status) {
  const normalized = `${status || ''}`.toLowerCase();
  if (normalized === 'available') {
    return 'success';
  }
  if (normalized === 'preview' || normalized === 'unknown') {
    return 'warning';
  }
  if (normalized === 'unavailable' || normalized === 'unsupported') {
    return 'danger';
  }
  if (normalized === 'not-applicable') {
    return 'warning';
  }
  return 'informative';
}

function priorityBadgeColor(importance) {
  const normalized = `${importance || 'medium'}`.toLowerCase();
  if (normalized === 'high') return 'danger';
  if (normalized === 'medium') return 'warning';
  return 'informative';
}

function runModeIcon(mode) {
  const normalized = `${mode || ''}`.toLowerCase();
  if (normalized === 'inventory') return <DocumentDatabase20Regular />;
  return <Globe20Regular />;
}

function formatCapabilityStatus(status) {
  const normalized = `${status || ''}`.toLowerCase();
  if (normalized === 'not-applicable') return 'N/A';
  return status || 'unknown';
}

function statusSurface(status, themeMode) {
  const palette = themeMode === 'dark' ? STATUS_SURFACE_DARK : STATUS_SURFACE_LIGHT;
  return palette[status] || (themeMode === 'dark'
    ? { borderColor: '#7d8590', backgroundColor: 'rgba(40, 50, 64, 0.56)', accentColor: '#c9d1d9' }
    : { borderColor: '#c7d4e5', backgroundColor: '#f8fafc', accentColor: '#243447' });
}

function metadataDiffRows(details, sourceRegion, targetRegion) {
  const sections = details?.rawSections || details?.sections || [];
  return sections.flatMap((section) => {
    const title = `${section?.title || ''}`;
    if (!title.startsWith('Only in ')) {
      return [];
    }
    const availableIn = title.replace('Only in ', '');
    return (section.items || []).map((item) => ({
      key: `${availableIn}-${item.resourceType}`,
      label: item.label || item.resourceType,
      resourceType: item.resourceType,
      availableIn,
      oppositeRegion: availableIn === sourceRegion ? targetRegion : sourceRegion,
    }));
  });
}

function zoneSupportTone(mode) {
  const normalized = `${mode || ''}`.toLowerCase();
  if (normalized === 'both' || normalized === 'zonal' || normalized === 'zone-redundant') {
    return 'brand';
  }
  if (normalized === 'region-without-zones' || normalized === 'zone-support-unverified') {
    return 'warning';
  }
  if (normalized === 'regional') {
    return 'informative';
  }
  if (normalized === 'unknown') {
    return 'warning';
  }
  if (normalized.includes('unavailable')) {
    return 'danger';
  }
  return 'informative';
}

function differenceBadgeColor(status) {
  const normalized = `${status || ''}`.toLowerCase();
  if (normalized.includes('source')) {
    return 'warning';
  }
  if (normalized.includes('target')) {
    return 'brand';
  }
  if (normalized.includes('match') || normalized.includes('full')) {
    return 'success';
  }
  if (normalized.includes('unavailable')) {
    return 'danger';
  }
  return 'informative';
}

function formatAvailabilityLabel(status, sourceRegion, targetRegion, compact = false) {
  const normalized = `${status || ''}`.toLowerCase();
  if (normalized.includes('source')) {
    return compact ? (sourceRegion || 'source') : `${sourceRegion || 'source'} only`;
  }
  if (normalized.includes('target')) {
    return compact ? (targetRegion || 'target') : `${targetRegion || 'target'} only`;
  }
  if (normalized.includes('match') || normalized.includes('full')) {
    return compact ? 'both' : 'both regions';
  }
  if (normalized.includes('unavailable')) {
    return compact ? 'none' : 'not available';
  }
  return status || 'mixed';
}

function compactStatusLabel(status, sourceRegion, targetRegion) {
  return formatAvailabilityLabel(status, sourceRegion, targetRegion, true);
}

function familyRegionStatus(family) {
  if (family?.sourceCount && family?.targetCount) {
    return 'FULL_MATCH';
  }
  if (family?.sourceCount) {
    return 'SOURCE_EXTENDED';
  }
  if (family?.targetCount) {
    return 'TARGET_EXTENDED';
  }
  return 'UNAVAILABLE';
}

function familyRestrictionSummary(family, sourceRegion, targetRegion) {
  const parts = [];
  if (family?.sourceRestrictedCount) {
    parts.push(`${family.sourceRestrictedCount} restricted in ${sourceRegion}`);
  }
  if (family?.targetRestrictedCount) {
    parts.push(`${family.targetRestrictedCount} restricted in ${targetRegion}`);
  }
  return parts.join(' • ');
}

function buildThemeVars(themeMode) {
  if (themeMode === 'dark') {
    return {
      '--app-shell-start': '#0f1724',
      '--app-shell-end': '#16253a',
      '--app-card-bg': 'rgba(17, 24, 39, 0.82)',
      '--app-card-header-bg': 'rgba(56, 189, 248, 0.08)',
      '--app-card-subtle-bg': 'rgba(30, 41, 59, 0.92)',
      '--app-grid-line': 'rgba(71, 85, 105, 0.78)',
      '--app-grid-header-bg': 'rgba(30, 41, 59, 0.98)',
      '--app-soft-shadow': '0 18px 40px rgba(2, 8, 23, 0.28)',
      '--app-run-bg': 'rgba(30, 41, 59, 0.92)',
      '--app-run-selected-bg': 'rgba(17, 94, 136, 0.88)',
      '--app-summary-a': 'rgba(14, 116, 144, 0.16)',
      '--app-summary-b': 'rgba(8, 145, 178, 0.16)',
      '--app-summary-c': 'rgba(168, 85, 247, 0.14)',
      '--app-summary-d': 'rgba(22, 163, 74, 0.14)',
    };
  }

  return {
    '--app-shell-start': '#f5f7fb',
    '--app-shell-end': '#dfeefc',
    '--app-card-bg': 'rgba(255, 255, 255, 0.92)',
    '--app-card-header-bg': 'rgba(14, 165, 233, 0.08)',
    '--app-card-subtle-bg': 'rgba(244, 248, 252, 0.95)',
    '--app-grid-line': '#d9e2ec',
    '--app-grid-header-bg': '#eaf2f9',
    '--app-soft-shadow': '0 14px 36px rgba(15, 23, 42, 0.08)',
    '--app-run-bg': 'rgba(255, 255, 255, 0.88)',
    '--app-run-selected-bg': 'rgba(225, 239, 255, 0.96)',
    '--app-summary-a': 'rgba(14, 116, 144, 0.09)',
    '--app-summary-b': 'rgba(34, 197, 94, 0.08)',
    '--app-summary-c': 'rgba(245, 158, 11, 0.10)',
    '--app-summary-d': 'rgba(168, 85, 247, 0.08)',
  };
}

function formatTimestamp(value) {
  if (!value) {
    return '';
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function formatPricingSummary(pricingSummary) {
  if (!pricingSummary) {
    return '';
  }

  const price = pricingSummary.retailPrice ?? pricingSummary.unitPrice ?? pricingSummary.price;
  if (price === null || price === undefined || price === '') {
    return '';
  }

  const numericPrice = typeof price === 'number' ? price : Number(price);
  const formattedPrice = Number.isFinite(numericPrice) ? numericPrice.toLocaleString(undefined, { maximumFractionDigits: 6 }) : `${price}`;
  const currency = pricingSummary.currencyCode || '';
  const unit = pricingUnitSuffix(pricingSummary.unitOfMeasure, {
    priceType: pricingSummary.priceType,
    reservationTerm: pricingSummary.reservationTerm,
  });
  const source = pricingSummary.source ? `${String(pricingSummary.source).charAt(0).toUpperCase()}${String(pricingSummary.source).slice(1)}` : 'Pricing';

  return `${source}: ${formattedPrice}${currency ? ` ${currency}` : ''}${unit}`.trim();
}

function formatPriceValue(price, currencyCode, unitOfMeasure) {
  return formatPriceValueWithContext(price, currencyCode, unitOfMeasure, {});
}

function pricingUnitSuffix(unitOfMeasure, { priceType = '', reservationTerm = '' } = {}) {
  const normalizedUnit = `${unitOfMeasure || ''}`.trim();
  if (!normalizedUnit) {
    return '';
  }

  const normalizedType = `${priceType || ''}`.trim().toLowerCase();
  const normalizedTerm = `${reservationTerm || ''}`.trim();
  if ((normalizedType === 'reservation' || normalizedType === 'savingsplan') && /^\d+\s*hour$/i.test(normalizedUnit)) {
    return normalizedTerm ? ` per month equivalent (${normalizedTerm.toLowerCase()})` : ' per month equivalent';
  }

  return ` per ${normalizedUnit}`;
}

function reservationMonths(reservationTerm = '') {
  const normalizedTerm = `${reservationTerm || ''}`.trim().toLowerCase();
  const yearsMatch = normalizedTerm.match(/(\d+)\s*year/);
  if (yearsMatch) {
    return Number(yearsMatch[1]) * 12;
  }
  const monthsMatch = normalizedTerm.match(/(\d+)\s*month/);
  if (monthsMatch) {
    return Number(monthsMatch[1]);
  }
  return 0;
}

function monthlyEquivalentPrice(price, { priceType = '', reservationTerm = '' } = {}) {
  const normalizedType = `${priceType || ''}`.trim().toLowerCase();
  if (normalizedType !== 'reservation' && normalizedType !== 'savingsplan') {
    return price;
  }

  const months = reservationMonths(reservationTerm);
  if (!months) {
    return price;
  }

  const numericPrice = typeof price === 'number' ? price : Number(price);
  if (!Number.isFinite(numericPrice)) {
    return price;
  }

  return numericPrice / months;
}

function formatPriceValueWithContext(price, currencyCode, unitOfMeasure, { priceType = '', reservationTerm = '' } = {}) {
  if (price === null || price === undefined || price === '') {
    return 'Unavailable';
  }

  const normalizedPrice = monthlyEquivalentPrice(price, { priceType, reservationTerm });
  const numericPrice = typeof normalizedPrice === 'number' ? normalizedPrice : Number(normalizedPrice);
  const formattedPrice = Number.isFinite(numericPrice)
    ? numericPrice.toLocaleString(undefined, { maximumFractionDigits: 6 })
    : `${normalizedPrice}`;
  return `${formattedPrice}${currencyCode ? ` ${currencyCode}` : ''}${pricingUnitSuffix(unitOfMeasure, { priceType, reservationTerm })}`.trim();
}

function formatPricingOverlayValue(item, side) {
  const price = side === 'target' ? item?.targetPrice : item?.sourcePrice;
  const priceType = side === 'target'
    ? (item?.targetPriceType || item?.sourcePriceType || '')
    : (item?.sourcePriceType || item?.targetPriceType || '');
  const reservationTerm = side === 'target'
    ? (item?.targetReservationTerm || item?.sourceReservationTerm || '')
    : (item?.sourceReservationTerm || item?.targetReservationTerm || '');
  return formatPriceValueWithContext(price, item?.currencyCode, item?.unitOfMeasure, { priceType, reservationTerm });
}

function capabilityGuidance(capability, sourceRegion, targetRegion) {
  const sourceNotes = `${capability?.sourceNotes || ''}`.trim();
  const targetNotes = `${capability?.targetNotes || ''}`.trim();
  if (sourceNotes && targetNotes && sourceNotes === targetNotes) {
    return sourceNotes;
  }
  if (sourceNotes && targetNotes) {
    return `${sourceRegion}: ${sourceNotes}\n${targetRegion}: ${targetNotes}`;
  }
  return sourceNotes || targetNotes || 'No operator guidance provided.';
}

function pricingDisplayText(pricingSummary, pricingComparison) {
  const items = pricingComparison?.items || [];
  if (items.length) {
    const total = pricingComparison?.totalItems || items.length;
    return `Cost comparison: ${Math.min(items.length, 5)} of ${total} meter${total === 1 ? '' : 's'} shown`;
  }
  return formatPricingSummary(pricingSummary) || 'Pricing: unavailable';
}

function formatIdentityLabel(value) {
  const normalized = `${value || ''}`.trim();
  if (!normalized) {
    return '';
  }
  return normalized
    .split(/[-_]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function identityAliasText(serviceIdentity) {
  const aliases = serviceIdentity?.provenance?.serviceNames || [];
  const canonicalName = `${serviceIdentity?.canonicalServiceName || ''}`.toLowerCase();
  const filtered = aliases.filter((value) => `${value || ''}`.trim().toLowerCase() !== canonicalName);
  return filtered.slice(0, 3).join(' • ');
}

function resultCanonicalFamily(item) {
  const serviceIdentity = resultServiceIdentity(item);
  return `${serviceIdentity?.canonicalFamilyKey || serviceIdentity?.canonicalFamily || item?.service_family || ''}`.trim();
}

function resultFamilyValues(item) {
  const serviceIdentity = resultServiceIdentity(item);
  return [...new Set([
    `${item.service_family || ''}`.trim(),
    resultCanonicalFamily(item),
    `${serviceIdentity?.canonicalFamily || ''}`.trim(),
  ].filter(Boolean))];
}

function resultServiceIdentity(item) {
  if (item?._serviceIdentity) {
    return item._serviceIdentity;
  }
  const details = tryParseDetails(item?.details_json);
  return details?.serviceIdentity || null;
}

function resultCurated(item) {
  const details = tryParseDetails(item?.details_json);
  return details?.curated || null;
}

function resultHasIdentityFallback(item) {
  const serviceIdentity = resultServiceIdentity(item);
  return Boolean(serviceIdentity && (serviceIdentity.isFallbackIdentity || serviceIdentity.matched === false));
}

function resultSearchValues(item) {
  if (Array.isArray(item?._searchValues)) {
    return item._searchValues;
  }
  const serviceIdentity = resultServiceIdentity(item);
  return [
    item.service,
    item.provider,
    item.notes,
    serviceIdentity?.canonicalServiceName,
    serviceIdentity?.canonicalServiceId,
    serviceIdentity?.canonicalFamily,
    serviceIdentity?.matchedServiceKey,
    serviceIdentity?.providerNamespace,
    serviceIdentity?.identitySource,
    serviceIdentity?.matchStrategy,
    ...(serviceIdentity?.provenance?.serviceNames || []),
    ...(serviceIdentity?.provenance?.serviceFamilies || []),
    ...(serviceIdentity?.provenance?.productNames || []),
    ...(serviceIdentity?.provenance?.searchKeywords || []),
  ]
    .filter(Boolean)
    .map((value) => `${value}`.toLowerCase());
}

function resultSearchIndex(item) {
  if (item?._searchIndex) {
    return item._searchIndex;
  }
  return resultSearchValues(item).join('\n');
}

function resultAvailabilityValue(item) {
  return `${item?.availability || ''}`.trim().toLowerCase();
}

function resultHasRegionGap(item) {
  const availability = resultAvailabilityValue(item);
  if (availability.includes('source_extended') || availability.includes('target_extended') || availability.includes('unavailable')) {
    return true;
  }

  const curated = resultCurated(item);
  if (!curated?.sourceRegion?.serviceAvailable || !curated?.targetRegion?.serviceAvailable) {
    return false;
  }

  const sourceHasZones = `${curated?.sourceRegion?.regionHasAvailabilityZones || ''}`.trim().toLowerCase();
  const targetHasZones = `${curated?.targetRegion?.regionHasAvailabilityZones || ''}`.trim().toLowerCase();
  return (sourceHasZones === 'true' && targetHasZones === 'false') || (sourceHasZones === 'false' && targetHasZones === 'true');
}

function resultHasPricingFollowUp(item) {
  const availability = resultAvailabilityValue(item);
  if (!(availability.includes('full_match') || availability.includes('available') || availability.includes('conditional'))) {
    return false;
  }

  const details = tryParseDetails(item?.details_json);
  if (!details) {
    return false;
  }

  const pricingComparison = details.pricingComparison;
  if (pricingComparison) {
    const comparisonCount = (pricingComparison.items?.length || 0) + (pricingComparison.rows?.length || 0) + (pricingComparison.groups?.length || 0);
    return comparisonCount === 0;
  }

  return !details.pricingSummary;
}

function resultIsMoveReady(item) {
  const availability = resultAvailabilityValue(item);
  return availability.includes('full_match') && !resultHasRegionGap(item) && !resultHasIdentityFallback(item) && !resultHasPricingFollowUp(item);
}

function resultTriageBucket(item) {
  if (resultHasRegionGap(item)) {
    return 'region-gap';
  }
  if (resultHasIdentityFallback(item)) {
    return 'identity-review';
  }
  if (resultHasPricingFollowUp(item)) {
    return 'pricing-follow-up';
  }
  if (resultIsMoveReady(item)) {
    return 'move-ready';
  }
  return 'other';
}

function triageRank(bucket) {
  switch (bucket) {
    case 'region-gap':
      return 0;
    case 'identity-review':
      return 1;
    case 'pricing-follow-up':
      return 2;
    case 'move-ready':
      return 3;
    default:
      return 4;
  }
}

function triageSummaryLabel(bucket) {
  switch (bucket) {
    case 'region-gap':
      return 'Check target-region coverage or availability-zone posture before planning this move.';
    case 'identity-review':
      return 'Review the canonical identity match before treating this row as aligned.';
    case 'pricing-follow-up':
      return 'Availability looks usable, but pricing evidence still needs follow-up.';
    case 'move-ready':
      return 'Service alignment looks clean for an initial move assessment.';
    default:
      return 'Open the details for capability, pricing, and provider context.';
  }
}

function compactPricingSummary(details) {
  if (!details) {
    return '';
  }

  if (details.layout === 'family-breakdown' || details.layout === 'sku-breakdown') {
    return 'Pricing is organized in the expanded family and SKU breakdown.';
  }

  const pricingComparison = details.pricingComparison;
  const hasPricingEvidence = Boolean(
    details.pricingSummary
    || (pricingComparison?.items?.length || 0) > 0
    || (pricingComparison?.rows?.length || 0) > 0
    || (pricingComparison?.groups?.length || 0) > 0
  );

  return hasPricingEvidence ? 'Pricing evidence is attached in the expanded view.' : '';
}

function regionAzSummaryValue(results, regionKey) {
  const values = new Set(
    results
      .map((item) => `${item?._details?.curated?.[regionKey]?.regionHasAvailabilityZones || ''}`.trim().toLowerCase())
      .filter(Boolean),
  );
  if (values.has('true')) {
    return 'Availability zones available';
  }
  if (values.has('false')) {
    return 'No availability zones';
  }
  return 'AZ posture not verified';
}

function regionAzSummaryTone(summary) {
  const normalized = `${summary || ''}`.toLowerCase();
  if (normalized.includes('availability zones available')) {
    return 'success';
  }
  if (normalized.includes('no availability zones')) {
    return 'warning';
  }
  return 'informative';
}

function pricingDeltaInfo(item, sourceRegion, targetRegion) {
  const delta = item?.delta;
  const deltaPercent = item?.deltaPercent;
  if (delta === null || delta === undefined || Number.isNaN(delta)) {
    return { tone: 'neutral', label: 'No direct match', detail: 'Meter not present in both regions' };
  }
  if (delta === 0) {
    return { tone: 'neutral', label: '= Same', detail: 'Prices are aligned' };
  }

  const cheaperRegion = item?.cheaperRegion === sourceRegion ? sourceRegion : item?.cheaperRegion === targetRegion ? targetRegion : null;
  const tone = delta > 0 ? 'negative' : 'positive';
  const sign = delta > 0 ? '+' : '-';
  const percent = typeof deltaPercent === 'number' && Number.isFinite(deltaPercent)
    ? ` (${sign}${Math.abs(deltaPercent).toFixed(Math.abs(deltaPercent) >= 10 ? 1 : 2)}%)`
    : '';
  return {
    tone,
    label: `${sign}${formatPriceValueWithContext(Math.abs(delta), item?.currencyCode, item?.unitOfMeasure, { priceType: item?.sourcePriceType || item?.targetPriceType, reservationTerm: item?.sourceReservationTerm || item?.targetReservationTerm })}`,
    detail: cheaperRegion ? `${cheaperRegion} is cheaper${percent}` : `Regional delta${percent}`,
  };
}

function pricingRegionDeltaInfo(item, region, sourceRegion, targetRegion) {
  const delta = item?.delta;
  const deltaPercent = item?.deltaPercent;
  if (delta === null || delta === undefined || Number.isNaN(delta)) {
    return { tone: 'neutral', label: 'No direct match', detail: 'Meter not present in both regions' };
  }
  if (delta === 0) {
    return { tone: 'neutral', label: '= Same', detail: 'Prices aligned' };
  }

  const currentRegion = region === 'source' ? sourceRegion : targetRegion;
  const cheaperRegion = item?.cheaperRegion === sourceRegion ? sourceRegion : item?.cheaperRegion === targetRegion ? targetRegion : null;
  const regionIsCheaper = cheaperRegion
    ? cheaperRegion === currentRegion
    : region === 'source'
      ? delta < 0
      : delta > 0;
  const tone = regionIsCheaper ? 'positive' : 'negative';
  const sign = regionIsCheaper ? '-' : '+';
  const percent = typeof deltaPercent === 'number' && Number.isFinite(deltaPercent)
    ? ` (${Math.abs(deltaPercent).toFixed(Math.abs(deltaPercent) >= 10 ? 1 : 2)}%)`
    : '';

  return {
    tone,
    label: `${sign}${formatPriceValueWithContext(Math.abs(delta), item?.currencyCode, item?.unitOfMeasure, { priceType: item?.sourcePriceType || item?.targetPriceType, reservationTerm: item?.sourceReservationTerm || item?.targetReservationTerm })}`,
    detail: `${regionIsCheaper ? 'Cheaper' : 'Higher'}${percent}`,
  };
}

function pricingCellTone(item, region, sourceRegion, targetRegion) {
  const price = region === 'source' ? item?.sourcePrice : item?.targetPrice;
  if (price === null || price === undefined) {
    return { tone: 'neutral', label: 'Unavailable' };
  }
  if (item?.cheaperRegion === 'same') {
    return { tone: 'neutral', label: '= Same' };
  }
  if ((region === 'source' && item?.cheaperRegion === sourceRegion) || (region === 'target' && item?.cheaperRegion === targetRegion)) {
    return { tone: 'positive', label: '- Cheaper' };
  }
  if (item?.cheaperRegion) {
    return { tone: 'negative', label: '+ Higher' };
  }
  return { tone: 'neutral', label: 'No match' };
}

function normalizeLookupValue(value) {
  return `${value || ''}`.toLowerCase().replace(/[^a-z0-9]+/g, '');
}

function buildLookupCandidates(values) {
  return [...new Set(values.map((value) => normalizeLookupValue(value)).filter(Boolean))];
}

function extractParentheticalValues(value) {
  return [...`${value || ''}`.matchAll(/\(([^)]+)\)/g)].map((match) => match[1]).filter(Boolean);
}

function vmFamilyKeyFromArmSku(value) {
  let normalized = `${value || ''}`.toLowerCase().trim();
  if (!normalized) {
    return '';
  }

  normalized = normalized
    .replace(/^(standard|basic)[_-]?/, '')
    .replace(/[^a-z0-9_]+/g, '');

  const versionMatch = normalized.match(/(?:_|)(v\d+)$/);
  const version = versionMatch?.[1] || '';
  const withoutVersion = version ? normalized.slice(0, normalized.lastIndexOf(version)).replace(/_+$/g, '') : normalized;
  const baseToken = (withoutVersion.split('_')[0] || withoutVersion).replace(/\d+/g, '');
  return normalizeLookupValue(`${baseToken}${version}`);
}

function vmFamilyKeysFromText(value) {
  return [...new Set(
    [...`${value || ''}`.toLowerCase().matchAll(/\b([a-z]{1,8}[a-z0-9]*v\d+)\b/g)]
      .map((match) => normalizeLookupValue(match[1]))
      .filter(Boolean),
  )];
}

function pricingComparisonSortValue(item) {
  const lowestPrice = [item?.sourcePrice, item?.targetPrice]
    .filter((value) => typeof value === 'number' && Number.isFinite(value));
  return lowestPrice.length ? Math.min(...lowestPrice) : Number.POSITIVE_INFINITY;
}

function bestMatchedPricingItem(items) {
  return [...items].sort((left, right) => {
    const leftMatched = left?.sourceAvailable && left?.targetAvailable ? 0 : 1;
    const rightMatched = right?.sourceAvailable && right?.targetAvailable ? 0 : 1;
    if (leftMatched !== rightMatched) {
      return leftMatched - rightMatched;
    }

    const leftPrice = pricingComparisonSortValue(left);
    const rightPrice = pricingComparisonSortValue(right);
    if (leftPrice !== rightPrice) {
      return leftPrice - rightPrice;
    }

    return `${left?.label || ''}`.localeCompare(`${right?.label || ''}`);
  })[0] || null;
}

function diskPricingMatch(rowSku, comparison) {
  const items = comparison?.items || [];
  if (!items.length) {
    return null;
  }

  const baseSku = `${rowSku || ''}`.replace(/\s*\([^)]*\)\s*/g, ' ').trim();
  const rowCandidates = buildLookupCandidates([
    rowSku,
    baseSku,
    ...extractParentheticalValues(rowSku),
  ]);

  if (!rowCandidates.length) {
    return null;
  }

  const matches = items.filter((item) => {
    const itemCandidates = buildLookupCandidates([
      item?.armSkuName,
      item?.sourceArmSkuName,
      item?.targetArmSkuName,
      item?.skuName,
      item?.productName,
      item?.meterName,
      item?.label,
    ]);

    return rowCandidates.some((candidate) => itemCandidates.some((itemCandidate) => itemCandidate === candidate || itemCandidate.includes(candidate) || candidate.includes(itemCandidate)));
  });

  return matches.length ? bestMatchedPricingItem(matches) : null;
}

function vmFamilyPricingMatch(family, comparison) {
  const items = comparison?.items || [];
  if (!items.length) {
    return null;
  }

  const familyKey = normalizeLookupValue(family);
  if (!familyKey) {
    return null;
  }

  const matches = items.filter((item) => {
    const itemKeys = new Set([
      vmFamilyKeyFromArmSku(item?.armSkuName),
      vmFamilyKeyFromArmSku(item?.sourceArmSkuName),
      vmFamilyKeyFromArmSku(item?.targetArmSkuName),
      ...vmFamilyKeysFromText(item?.productName),
      ...vmFamilyKeysFromText(item?.skuName),
      ...vmFamilyKeysFromText(item?.meterName),
      ...vmFamilyKeysFromText(item?.label),
    ].filter(Boolean));

    return itemKeys.has(familyKey);
  });

  return matches.length ? bestMatchedPricingItem(matches) : null;
}

function pricingToneClass(tone, styles) {
  if (tone === 'positive') {
    return styles.pricingDeltaNegative;
  }
  if (tone === 'negative') {
    return styles.pricingDeltaPositive;
  }
  return styles.pricingDeltaNeutral;
}

function pricingMeterReference(item, region) {
  if (!item) {
    return '';
  }
  return region === 'source'
    ? item?.sourceMeterName || item?.meterName || item?.skuName || item?.productName || ''
    : item?.targetMeterName || item?.meterName || item?.skuName || item?.productName || '';
}

function compactPricingReference(item, region) {
  const reference = `${pricingMeterReference(item, region) || ''}`.replace(/\s+/g, ' ').trim();
  if (!reference) {
    return '';
  }
  return reference.length > 54 ? `${reference.slice(0, 51)}...` : reference;
}

function PriceDetailCell({
  topValue,
  priceText,
  toneLabel,
  toneClassName,
  referenceText,
  styles,
}) {
  return (
    <TableCellLayout className={styles.detailCellStack}>
      {topValue !== null && topValue !== undefined ? <div className={styles.detailValueStrong}>{topValue}</div> : null}
      {priceText ? <Caption1 className={styles.detailValueSubtle}>{priceText}</Caption1> : null}
      {toneLabel ? <Caption1 className={toneClassName}>{toneLabel}</Caption1> : null}
      {referenceText ? <Caption1 className={styles.detailValueMono}>{referenceText}</Caption1> : null}
    </TableCellLayout>
  );
}

function pricingDetailsGroups(pricingDetails) {
  return Array.isArray(pricingDetails?.groups) ? pricingDetails.groups : [];
}

function pricingDetailsCountLabel(pricingDetails) {
  if (!pricingDetails) {
    return '';
  }
  if (pricingDetails.kind === 'vm') {
    return `${pricingDetails.rowCount || 0} SKU size row${pricingDetails.rowCount === 1 ? '' : 's'}`;
  }
  return `${pricingDetails.matchedItemCount || 0} matched meter${pricingDetails.matchedItemCount === 1 ? '' : 's'}`;
}

function normalizePricingFilterValue(value) {
  return `${value || ''}`.trim().toLowerCase();
}

function collectPricingFilterOptions(values) {
  return [...new Set(values.map((value) => `${value || ''}`.trim()).filter(Boolean))].sort((left, right) => left.localeCompare(right));
}

function pricingFieldMatches(values, filterValue, { exact = false } = {}) {
  if (!filterValue) {
    return true;
  }

  const normalizedValues = values.map((value) => normalizePricingFilterValue(value)).filter(Boolean);
  return exact
    ? normalizedValues.includes(filterValue)
    : normalizedValues.some((value) => value.includes(filterValue));
}

function pricingTextMatches(values, filterValue) {
  if (!filterValue) {
    return true;
  }
  return values.some((value) => `${value || ''}`.toLowerCase().includes(filterValue));
}

function hasActivePricingFilters(filters) {
  return Boolean(
    normalizePricingFilterValue(filters?.productName)
    || normalizePricingFilterValue(filters?.skuName)
    || normalizePricingFilterValue(filters?.meterName)
  );
}

function pricingItemMatchesFilters(item, filters, extraSkuValues = []) {
  const productFilter = normalizePricingFilterValue(filters?.productName);
  const skuFilter = normalizePricingFilterValue(filters?.skuName);
  const meterFilter = normalizePricingFilterValue(filters?.meterName);

  return pricingFieldMatches([
    item?.productName,
    item?.sourceProductName,
    item?.targetProductName,
    item?.label,
  ], productFilter, { exact: true })
    && pricingFieldMatches([
      item?.skuName,
      item?.sourceSkuName,
      item?.targetSkuName,
      item?.armSkuName,
      ...extraSkuValues,
    ], skuFilter, { exact: true })
    && pricingTextMatches([
      item?.meterName,
      item?.sourceMeterName,
      item?.targetMeterName,
    ], meterFilter);
}

function pricingFilterOptionsFromItems(items, extraSkuValues = []) {
  return {
    productNames: collectPricingFilterOptions(items.flatMap((item) => [
      item?.productName,
      item?.sourceProductName,
      item?.targetProductName,
      item?.label,
    ])),
    skuNames: collectPricingFilterOptions(items.flatMap((item) => [
      item?.skuName,
      item?.sourceSkuName,
      item?.targetSkuName,
      item?.armSkuName,
      ...extraSkuValues(item),
    ])),
  };
}

function formatPricingScopeOption(value) {
  const compactValue = `${value || ''}`.trim().replace(/\s+/g, ' ');
  if (!compactValue) {
    return '';
  }

  const normalizedValue = compactValue.toLowerCase();
  if (normalizedValue.includes('data lake storage gen2') && normalizedValue.includes('flat namespace')) {
    return 'Azure Data Lake Storage Gen2 Flat Namespace';
  }
  if (normalizedValue.includes('data lake storage gen2') && normalizedValue.includes('hierarchical namespace')) {
    return 'Azure Data Lake Storage Gen2 Hierarchical Namespace';
  }
  if (normalizedValue === 'storage') {
    return 'Azure Storage';
  }
  return compactValue;
}

function pricingFilterLabels(kind = '') {
  if (kind === 'vm') {
    return {
      title: 'Refine pricing view',
      description: 'Start with service scope, then narrow to VM size and charge detail.',
      productLabel: 'Service scope',
      productAllLabel: 'All service scopes',
      skuLabel: 'VM size',
      skuAllLabel: 'All VM sizes',
      meterLabel: 'Charge detail',
      meterPlaceholder: 'Filter charge details',
      emptyState: 'No pricing rows match the current service scope, VM size, and charge detail filters.',
    };
  }

  if (kind === 'disk') {
    return {
      title: 'Refine pricing view',
      description: 'Start with service scope, then narrow to disk SKU and charge detail.',
      productLabel: 'Service scope',
      productAllLabel: 'All service scopes',
      skuLabel: 'Disk SKU',
      skuAllLabel: 'All disk SKUs',
      meterLabel: 'Charge detail',
      meterPlaceholder: 'Filter charge details',
      emptyState: 'No pricing items match the current service scope, disk SKU, and charge detail filters.',
    };
  }

  return {
    title: 'Refine pricing view',
    description: 'Start with service scope, then narrow to SKU and charge detail.',
    productLabel: 'Service scope',
    productAllLabel: 'All service scopes',
    skuLabel: 'SKU or plan',
    skuAllLabel: 'All SKUs and plans',
    meterLabel: 'Charge detail',
    meterPlaceholder: 'Filter charge details',
    emptyState: 'No pricing items match the current service scope, SKU, and charge detail filters.',
  };
}

function PricingFilterBar({ filters, setFilters, filteredCount, totalCount, itemLabel, filterOptions, filterLabels, styles }) {
  const activeFilters = hasActivePricingFilters(filters);
  const labels = filterLabels || pricingFilterLabels();

  return (
    <div className={styles.pricingFilterBar}>
      <div className={styles.pricingFilterHeader}>
        <div className={styles.pricingFilterMeta}>
          <Caption1>{labels.title}</Caption1>
          <Caption1>
            Showing {filteredCount} of {totalCount} {itemLabel}{totalCount === 1 ? '' : 's'}
          </Caption1>
          <Caption1>{labels.description}</Caption1>
        </div>
        <Button
          appearance="secondary"
          size="small"
          disabled={!activeFilters}
          onClick={() => setFilters(emptyPricingFilters)}
        >
          Clear filters
        </Button>
      </div>
      <div className={styles.pricingFilterGrid}>
        <Field label={labels.productLabel}>
          <Dropdown
            value={filters.productName ? formatPricingScopeOption(filters.productName) : labels.productAllLabel}
            selectedOptions={[filters.productName || 'all']}
            onOptionSelect={(_, data) => setFilters((current) => ({
              ...current,
              productName: data.optionValue === 'all' ? '' : (data.optionValue || ''),
            }))}
          >
            <Option value="all" text={labels.productAllLabel}>{labels.productAllLabel}</Option>
            {(filterOptions?.productNames || []).map((value) => {
              const optionLabel = formatPricingScopeOption(value);
              return (
                <Option key={value} value={value} text={optionLabel}>{optionLabel}</Option>
              );
            })}
          </Dropdown>
        </Field>
        <Field label={labels.skuLabel}>
          <Dropdown
            value={filters.skuName || labels.skuAllLabel}
            title={filters.skuName || labels.skuAllLabel}
            selectedOptions={[filters.skuName || 'all']}
            onOptionSelect={(_, data) => setFilters((current) => ({
              ...current,
              skuName: data.optionValue === 'all' ? '' : (data.optionValue || ''),
            }))}
          >
            <Option value="all" text={labels.skuAllLabel}>{labels.skuAllLabel}</Option>
            {(filterOptions?.skuNames || []).map((value) => (
              <Option key={value} value={value} text={value}>{value}</Option>
            ))}
          </Dropdown>
        </Field>
        <Field label={labels.meterLabel}>
          <Input
            value={filters.meterName}
            placeholder={labels.meterPlaceholder}
            onChange={(_, data) => setFilters((current) => ({ ...current, meterName: data.value }))}
          />
        </Field>
      </div>
    </div>
  );
}

function formatPricingOfferLabel(item) {
  if (item?.offerLabel) {
    return item.offerLabel;
  }

  const priceType = `${item?.sourcePriceType || item?.targetPriceType || ''}`;
  const reservationTerm = `${item?.sourceReservationTerm || item?.targetReservationTerm || ''}`;
  if (priceType === 'Consumption') {
    return 'Pay as you go';
  }
  if (priceType === 'Reservation' && reservationTerm) {
    return `Reserved instance ${reservationTerm.toLowerCase()}`;
  }
  if (priceType === 'SavingsPlan' && reservationTerm) {
    return `Savings plan ${reservationTerm.toLowerCase()}`;
  }
  if (priceType === 'Reservation') {
    return 'Reserved instance';
  }
  if (priceType === 'SavingsPlan') {
    return 'Savings plan';
  }
  return item?.label || item?.meterName || item?.skuName || item?.productName || 'Pricing item';
}

function pricingReferenceText(item) {
  return `${item?.meterName || item?.sourceMeterName || item?.targetMeterName || item?.skuName || item?.productName || ''}`.trim();
}

function vmPricingModels(pricingDetails) {
  return Array.isArray(pricingDetails?.models) ? pricingDetails.models : [];
}

function vmPricingRows(pricingDetails) {
  return Array.isArray(pricingDetails?.rows) ? pricingDetails.rows : [];
}

function VmPricingOverlayTable({ pricingDetails, sourceRegion, targetRegion, pricingFilters, styles }) {
  const models = vmPricingModels(pricingDetails);
  const rows = vmPricingRows(pricingDetails);
  const [pageNumber, setPageNumber] = useState(1);
  const filteredRows = hasActivePricingFilters(pricingFilters)
    ? rows.filter((row) => Object.values(row?.offers || {}).some((item) => pricingItemMatchesFilters(item, pricingFilters, [row?.sku])))
    : rows;

  useEffect(() => {
    setPageNumber(1);
  }, [filteredRows.length, models.length, pricingFilters?.productName, pricingFilters?.skuName, pricingFilters?.meterName]);

  if (!models.length || !rows.length) {
    return null;
  }

  if (!filteredRows.length) {
    return <div className={styles.emptyBlock}>No pricing rows match the current product, SKU, and meter filters.</div>;
  }

  const totalPages = Math.max(1, Math.ceil(filteredRows.length / detailTablePageSize));
  const safePageNumber = Math.min(pageNumber, totalPages);
  const pagedRows = filteredRows.slice((safePageNumber - 1) * detailTablePageSize, safePageNumber * detailTablePageSize);
  const shownEnd = Math.min(safePageNumber * detailTablePageSize, filteredRows.length);
  const shownStart = filteredRows.length ? ((safePageNumber - 1) * detailTablePageSize) + 1 : 0;
  return (
    <>
      <div className={styles.pricingMatrixViewport}>
        <div className={styles.pricingMatrixTable}>
          {pagedRows.map((row) => {
            const offers = row?.offers || {};
            return (
              <section key={row.key || row.sku} className={styles.pricingMatrixRow} aria-label={`SKU size ${row.sku}`}>
                <div className={`${styles.pricingMatrixCell} ${styles.pricingMatrixSkuCell}`}>
                  <div className={styles.pricingMatrixSkuStack}>
                    <Caption1 className={styles.pricingMatrixSkuLabel}>SKU size</Caption1>
                    <div className={styles.pricingMatrixSkuValue} title={row.sku}>{row.sku}</div>
                  </div>
                </div>
                <div className={styles.pricingMatrixOffers}>
                  {models.map((model) => {
                    const item = offers[model.key] || null;
                    const sourceDelta = item ? pricingRegionDeltaInfo(item, 'source', sourceRegion, targetRegion) : null;
                    const targetDelta = item ? pricingRegionDeltaInfo(item, 'target', sourceRegion, targetRegion) : null;
                    return (
                      <div key={`${row.key || row.sku}-${model.key}`} className={styles.pricingMatrixCell}>
                        <div className={styles.pricingMatrixModelTitle}>{model.title}</div>
                        {item ? (
                          <div className={styles.pricingNestedTable}>
                            <div className={styles.pricingNestedHeader}>
                              <div className={styles.pricingNestedHeaderCell}>Region</div>
                              <div className={styles.pricingNestedHeaderCell}>Price</div>
                              <div className={styles.pricingNestedHeaderCell}>Delta</div>
                            </div>
                            <div className={styles.pricingNestedRow}>
                              <div className={`${styles.pricingNestedCell} ${styles.pricingNestedRegionCell}`}>{sourceRegion}</div>
                              <div className={styles.pricingNestedCell}>{formatPricingOverlayValue(item, 'source')}</div>
                              <div className={styles.pricingNestedCell}>
                                <div className={`${styles.pricingNestedDeltaLabel} ${pricingToneClass(sourceDelta?.tone, styles)}`}>{sourceDelta?.label}</div>
                                {sourceDelta?.detail ? <Caption1 className={styles.pricingNestedDeltaDetail}>{sourceDelta.detail}</Caption1> : null}
                              </div>
                            </div>
                            <div className={styles.pricingNestedRow}>
                              <div className={`${styles.pricingNestedCell} ${styles.pricingNestedRegionCell}`}>{targetRegion}</div>
                              <div className={styles.pricingNestedCell}>{formatPricingOverlayValue(item, 'target')}</div>
                              <div className={styles.pricingNestedCell}>
                                <div className={`${styles.pricingNestedDeltaLabel} ${pricingToneClass(targetDelta?.tone, styles)}`}>{targetDelta?.label}</div>
                                {targetDelta?.detail ? <Caption1 className={styles.pricingNestedDeltaDetail}>{targetDelta.detail}</Caption1> : null}
                              </div>
                            </div>
                          </div>
                        ) : (
                          <Caption1 className={styles.pricingMatrixUnavailable}>No direct match</Caption1>
                        )}
                      </div>
                    );
                  })}
                </div>
              </section>
            );
          })}
        </div>
      </div>

      <DetailTablePager
        pageNumber={safePageNumber}
        totalPages={totalPages}
        shownStart={shownStart}
        shownEnd={shownEnd}
        totalItems={filteredRows.length}
        onPrevious={() => setPageNumber((current) => Math.max(1, current - 1))}
        onNext={() => setPageNumber((current) => Math.min(totalPages, current + 1))}
        styles={styles}
      />
    </>
  );
}

function PricingOverlayDialog({ pricingDetails, pricingItem, rowLabel, sourceRegion, targetRegion, styles }) {
  const groups = pricingDetailsGroups(pricingDetails);
  const isVmMatrix = pricingDetails?.kind === 'vm' && vmPricingModels(pricingDetails).length && vmPricingRows(pricingDetails).length;
  const [pricingFilters, setPricingFilters] = useState(emptyPricingFilters);
  const overlayFilterLabels = pricingFilterLabels(pricingDetails?.kind);
  if (!groups.length && !isVmMatrix) {
    return null;
  }

  const representativeDelta = pricingItem ? pricingDeltaInfo(pricingItem, sourceRegion, targetRegion) : null;
  const pricingModelCount = pricingDetails?.kind === 'vm' && pricingDetails?.models?.length ? pricingDetails.models.length : 0;
  const overlayFilterOptions = isVmMatrix
    ? pricingFilterOptionsFromItems(
      vmPricingRows(pricingDetails).flatMap((row) => Object.values(row?.offers || {})),
      () => []
    )
    : pricingFilterOptionsFromItems(
      groups.flatMap((group) => group.items || []),
      () => []
    );
  if (isVmMatrix) {
    overlayFilterOptions.skuNames = collectPricingFilterOptions(vmPricingRows(pricingDetails).flatMap((row) => [
      row?.sku,
      ...Object.values(row?.offers || {}).flatMap((item) => [item?.skuName, item?.sourceSkuName, item?.targetSkuName, item?.armSkuName]),
    ]));
  }
  const totalVmRows = vmPricingRows(pricingDetails).length;
  const filteredVmRows = hasActivePricingFilters(pricingFilters)
    ? vmPricingRows(pricingDetails).filter((row) => Object.values(row?.offers || {}).some((item) => pricingItemMatchesFilters(item, pricingFilters, [row?.sku])))
    : vmPricingRows(pricingDetails);
  const totalGroupItems = groups.reduce((total, group) => total + ((group.items || []).length), 0);
  const filteredGroups = hasActivePricingFilters(pricingFilters)
    ? groups
      .map((group) => ({
        ...group,
        items: (group.items || []).filter((item) => pricingItemMatchesFilters(item, pricingFilters)),
      }))
      .filter((group) => group.items.length)
    : groups;
  const filteredGroupItems = filteredGroups.reduce((total, group) => total + ((group.items || []).length), 0);

  useEffect(() => {
    setPricingFilters(emptyPricingFilters);
  }, [pricingDetails?.kind, pricingDetails?.matchedItemCount, pricingDetails?.rowCount, rowLabel, sourceRegion, targetRegion]);

  return (
    <Dialog>
      <DialogTrigger disableButtonEnhancement>
        <Button appearance="outline" size="small" className={styles.pricingPreviewAction}>View pricing</Button>
      </DialogTrigger>
      <DialogSurface className={styles.pricingDialogSurface}>
        <DialogBody className={styles.pricingDialogBody}>
          <DialogTitle
            className={styles.pricingDialogTitle}
            action={(
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="subtle" icon={<Dismiss24Regular />} aria-label="Close pricing dialog" />
              </DialogTrigger>
            )}
          >
            <div className={styles.pricingDialogTitleHeader}>
              <div className={styles.pricingDialogTitleText}>{rowLabel} pricing</div>
              <div className={styles.pricingDialogSummaryMetrics}>
                <Badge appearance="tint" className={styles.pricingDialogMetricBadge}>{pricingDetailsCountLabel(pricingDetails)}</Badge>
                {pricingModelCount ? <Badge appearance="outline">{pricingModelCount} model{pricingModelCount === 1 ? '' : 's'}</Badge> : null}
              </div>
            </div>
            <Caption1 className={styles.pricingDialogContext}>{sourceRegion} vs {targetRegion}</Caption1>
          </DialogTitle>
          <DialogContent className={styles.pricingDialogContent}>
            <div className={styles.pricingDialogSummary}>
              <Caption1 className={styles.pricingDialogSummaryEyebrow}>Regional pricing snapshot</Caption1>
              <Caption1>{pricingDetailsCountLabel(pricingDetails)} across {sourceRegion} and {targetRegion}.</Caption1>
              {pricingItem ? (
                <Caption1>
                  Representative sample: {formatPricingOverlayValue(pricingItem, 'source')} in {sourceRegion} vs {formatPricingOverlayValue(pricingItem, 'target')} in {targetRegion}.
                </Caption1>
              ) : null}
              {representativeDelta ? <Caption1>{representativeDelta.detail || representativeDelta.label}</Caption1> : null}
            </div>

            <PricingFilterBar
              filters={pricingFilters}
              setFilters={setPricingFilters}
              filteredCount={isVmMatrix ? filteredVmRows.length : filteredGroupItems}
              totalCount={isVmMatrix ? totalVmRows : totalGroupItems}
              itemLabel={isVmMatrix ? 'pricing row' : 'pricing item'}
              filterOptions={overlayFilterOptions}
              filterLabels={overlayFilterLabels}
              styles={styles}
            />

            {isVmMatrix ? (
              <VmPricingOverlayTable pricingDetails={pricingDetails} sourceRegion={sourceRegion} targetRegion={targetRegion} pricingFilters={pricingFilters} styles={styles} />
            ) : (
              <div className={styles.pricingGroupList}>
                {filteredGroups.length ? filteredGroups.map((group) => (
                  <Card key={group.key || group.title} appearance="outline" size="small" className={styles.pricingGroupCard}>
                    <div className={styles.pricingGroupHeader}>
                      <Subtitle1>{group.title}</Subtitle1>
                      <Badge appearance="outline">{(group.items || []).length}</Badge>
                    </div>

                    <div className={styles.pricingGroupTable}>
                      <div className={styles.pricingGroupTableHeader}>
                        <div className={styles.pricingGroupHeaderCell}>Offer / meter</div>
                        <div className={styles.pricingGroupHeaderCell}>{sourceRegion}</div>
                        <div className={styles.pricingGroupHeaderCell}>{targetRegion}</div>
                        <div className={styles.pricingGroupHeaderCell}>Delta</div>
                      </div>

                      {(group.items || []).map((item) => {
                        const deltaInfo = pricingDeltaInfo(item, sourceRegion, targetRegion);
                        return (
                          <div key={item.key || `${group.key}-${formatPricingOfferLabel(item)}`} className={styles.pricingGroupRow}>
                            <div className={`${styles.pricingGroupCell} ${styles.pricingGroupNameCell}`}>
                              <div className={styles.detailValueStrong}>{formatPricingOfferLabel(item)}</div>
                              {pricingReferenceText(item) ? <Caption1 className={styles.detailValueMono}>{pricingReferenceText(item)}</Caption1> : null}
                            </div>
                            <div className={styles.pricingGroupCell}>
                              <div>{formatPricingOverlayValue(item, 'source')}</div>
                              <Caption1 className={styles.detailValueSubtle}>{item.sourceAvailable ? 'Available' : 'Unavailable'}</Caption1>
                            </div>
                            <div className={styles.pricingGroupCell}>
                              <div>{formatPricingOverlayValue(item, 'target')}</div>
                              <Caption1 className={styles.detailValueSubtle}>{item.targetAvailable ? 'Available' : 'Unavailable'}</Caption1>
                            </div>
                            <div className={styles.pricingGroupCell}>
                              <div className={pricingToneClass(deltaInfo.tone, styles)}>{deltaInfo.label}</div>
                              <Caption1>{deltaInfo.detail}</Caption1>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </Card>
                )) : <div className={styles.emptyBlock}>{overlayFilterLabels.emptyState}</div>}
              </div>
            )}
          </DialogContent>
          <DialogActions className={styles.pricingDialogActions}>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary" size="small">Close</Button>
            </DialogTrigger>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}

function PricingPreviewCell({ pricingItem, pricingDetails, rowLabel, sourceRegion, targetRegion, styles }) {
  const groups = pricingDetailsGroups(pricingDetails);
  const isVmMatrix = pricingDetails?.kind === 'vm' && vmPricingModels(pricingDetails).length && vmPricingRows(pricingDetails).length;
  const deltaInfo = pricingItem ? pricingDeltaInfo(pricingItem, sourceRegion, targetRegion) : null;
  const countLabel = pricingDetailsCountLabel(pricingDetails);

  return (
    <TableCellLayout className={styles.pricingPreviewCell}>
      <div className={styles.detailValueStrong}>{countLabel || 'No matched pricing'}</div>
      {pricingItem ? (
        <Caption1 className={styles.detailValueSubtle}>
          {formatPricingOverlayValue(pricingItem, 'source')} in {sourceRegion} vs {formatPricingOverlayValue(pricingItem, 'target')} in {targetRegion}
        </Caption1>
      ) : (
        <Caption1 className={styles.detailValueSubtle}>No representative pricing match</Caption1>
      )}
      {deltaInfo ? <Caption1 className={pricingToneClass(deltaInfo.tone, styles)}>{deltaInfo.detail || deltaInfo.label}</Caption1> : null}
      {(groups.length || isVmMatrix) ? (
        <PricingOverlayDialog
          pricingDetails={pricingDetails}
          pricingItem={pricingItem}
          rowLabel={rowLabel}
          sourceRegion={sourceRegion}
          targetRegion={targetRegion}
          styles={styles}
        />
      ) : null}
    </TableCellLayout>
  );
}

function formatStatusOptionLabel(status, sourceRegion, targetRegion) {
  if (status === 'all') {
    return 'All statuses';
  }
  return formatAvailabilityLabel(status, sourceRegion, targetRegion, false);
}

function rowPricing(row, comparison, matcher) {
  if (row?.pricing) {
    return row.pricing;
  }
  return matcher(row, comparison);
}

function DetailTablePager({ pageNumber, totalPages, shownStart, shownEnd, totalItems, onPrevious, onNext, styles }) {
  if (totalPages <= 1) {
    return null;
  }

  return (
    <div className={styles.pager}>
      <Caption1>Showing {shownStart}-{shownEnd} of {totalItems}</Caption1>
      <div className={styles.pagerActions}>
        <Button appearance="subtle" icon={<ChevronLeft20Regular />} onClick={onPrevious} disabled={pageNumber <= 1}>
          Previous
        </Button>
        <Caption1>Page {pageNumber} of {totalPages}</Caption1>
        <Button appearance="subtle" icon={<ChevronRight20Regular />} iconPosition="after" onClick={onNext} disabled={pageNumber >= totalPages}>
          Next
        </Button>
      </div>
    </div>
  );
}

function VmFamilyBreakdownTable({ details, comparison, row, styles }) {
  const families = details?.families || [];
  const [pageNumber, setPageNumber] = useState(1);

  useEffect(() => {
    setPageNumber(1);
  }, [families.length, row?.row_key]);

  const totalPages = Math.max(1, Math.ceil(families.length / detailTablePageSize));
  const safePageNumber = Math.min(pageNumber, totalPages);
  const pagedFamilies = families.slice((safePageNumber - 1) * detailTablePageSize, safePageNumber * detailTablePageSize);
  const shownEnd = Math.min(safePageNumber * detailTablePageSize, families.length);
  const shownStart = families.length ? ((safePageNumber - 1) * detailTablePageSize) + 1 : 0;

  return (
    <>
      <div className={styles.tableWrap}>
        <Table className={styles.detailDataTable}>
          <TableHeader>
            <TableRow>
              <TableHeaderCell>VM family</TableHeaderCell>
              <TableHeaderCell>{row.source_region} count</TableHeaderCell>
              <TableHeaderCell>{row.target_region} count</TableHeaderCell>
              <TableHeaderCell>Pricing</TableHeaderCell>
              <TableHeaderCell>Region</TableHeaderCell>
            </TableRow>
          </TableHeader>
          <TableBody>
            {pagedFamilies.map((family) => {
              const pricingItem = rowPricing(family, comparison, (currentFamily, currentComparison) => vmFamilyPricingMatch(currentFamily.family, currentComparison));
              const pricingDetails = family.pricingDetails || null;
              const regionStatus = familyRegionStatus(family);
              const restrictionSummary = familyRestrictionSummary(family, row.source_region, row.target_region);

              return (
                <TableRow key={`${row.provider}-${family.family}`}>
                  <TableCell><TableCellLayout>{family.family}</TableCellLayout></TableCell>
                  <TableCell><TableCellLayout className={styles.detailCellStack}><div className={styles.detailValueStrong}>{family.sourceCount}</div>{family.sourceRestrictedCount ? <Caption1 className={styles.detailValueSubtle}>{family.sourceDeployableCount} deployable • {family.sourceRestrictedCount} restricted</Caption1> : null}</TableCellLayout></TableCell>
                  <TableCell><TableCellLayout className={styles.detailCellStack}><div className={styles.detailValueStrong}>{family.targetCount}</div>{family.targetRestrictedCount ? <Caption1 className={styles.detailValueSubtle}>{family.targetDeployableCount} deployable • {family.targetRestrictedCount} restricted</Caption1> : null}</TableCellLayout></TableCell>
                  <TableCell>
                    <PricingPreviewCell
                      pricingItem={pricingItem}
                      pricingDetails={pricingDetails}
                      rowLabel={family.family}
                      sourceRegion={row.source_region}
                      targetRegion={row.target_region}
                      styles={styles}
                    />
                  </TableCell>
                  <TableCell><TableCellLayout className={styles.detailCellStack}><Badge appearance="filled" color={differenceBadgeColor(regionStatus)}>{compactStatusLabel(regionStatus, row.source_region, row.target_region)}</Badge>{restrictionSummary ? <Caption1 className={styles.detailValueSubtle}>{restrictionSummary}</Caption1> : null}</TableCellLayout></TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>

      <DetailTablePager
        pageNumber={safePageNumber}
        totalPages={totalPages}
        shownStart={shownStart}
        shownEnd={shownEnd}
        totalItems={families.length}
        onPrevious={() => setPageNumber((current) => Math.max(1, current - 1))}
        onNext={() => setPageNumber((current) => Math.min(totalPages, current + 1))}
        styles={styles}
      />
    </>
  );
}

function DiskSkuBreakdownTable({ details, comparison, row, styles }) {
  const skus = details?.skus || [];
  const [pageNumber, setPageNumber] = useState(1);

  useEffect(() => {
    setPageNumber(1);
  }, [skus.length, row?.row_key]);

  const totalPages = Math.max(1, Math.ceil(skus.length / detailTablePageSize));
  const safePageNumber = Math.min(pageNumber, totalPages);
  const pagedSkus = skus.slice((safePageNumber - 1) * detailTablePageSize, safePageNumber * detailTablePageSize);
  const shownEnd = Math.min(safePageNumber * detailTablePageSize, skus.length);
  const shownStart = skus.length ? ((safePageNumber - 1) * detailTablePageSize) + 1 : 0;

  return (
    <>
      <div className={styles.tableWrap}>
        <Table className={styles.detailDataTable}>
          <TableHeader>
            <TableRow>
              <TableHeaderCell>Disk SKU</TableHeaderCell>
              <TableHeaderCell>Tier</TableHeaderCell>
              <TableHeaderCell>{row.source_region}</TableHeaderCell>
              <TableHeaderCell>{row.target_region}</TableHeaderCell>
              <TableHeaderCell>Pricing</TableHeaderCell>
              <TableHeaderCell>Region</TableHeaderCell>
            </TableRow>
          </TableHeader>
          <TableBody>
            {pagedSkus.map((sku) => {
              const pricingItem = rowPricing(sku, comparison, (currentSku, currentComparison) => diskPricingMatch(currentSku.sku, currentComparison));
              const pricingDetails = sku.pricingDetails || null;
              const sourceRestricted = Boolean(sku.sourceRestricted);
              const targetRestricted = Boolean(sku.targetRestricted);

              return (
                <TableRow key={`${row.provider}-${sku.sku}`}>
                  <TableCell><TableCellLayout>{sku.sku}</TableCellLayout></TableCell>
                  <TableCell><TableCellLayout>{sku.tier}</TableCellLayout></TableCell>
                  <TableCell><TableCellLayout><Badge appearance="filled" color={sourceRestricted ? 'warning' : sku.sourceAvailable ? 'success' : 'danger'}>{sourceRestricted ? 'Restricted' : sku.sourceAvailable ? 'Available' : 'Not available'}</Badge></TableCellLayout></TableCell>
                  <TableCell><TableCellLayout><Badge appearance="filled" color={targetRestricted ? 'warning' : sku.targetAvailable ? 'success' : 'danger'}>{targetRestricted ? 'Restricted' : sku.targetAvailable ? 'Available' : 'Not available'}</Badge></TableCellLayout></TableCell>
                  <TableCell>
                    <PricingPreviewCell
                      pricingItem={pricingItem}
                      pricingDetails={pricingDetails}
                      rowLabel={sku.sku}
                      sourceRegion={row.source_region}
                      targetRegion={row.target_region}
                      styles={styles}
                    />
                  </TableCell>
                  <TableCell><TableCellLayout><Badge appearance="filled" color={differenceBadgeColor(sku.status)}>{compactStatusLabel(sku.status, row.source_region, row.target_region)}</Badge></TableCellLayout></TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>

      <DetailTablePager
        pageNumber={safePageNumber}
        totalPages={totalPages}
        shownStart={shownStart}
        shownEnd={shownEnd}
        totalItems={skus.length}
        onPrevious={() => setPageNumber((current) => Math.max(1, current - 1))}
        onNext={() => setPageNumber((current) => Math.min(totalPages, current + 1))}
        styles={styles}
      />
    </>
  );
}

function PricingComparisonPanel({ comparison, summary, sourceRegion, targetRegion, styles }) {
  const items = comparison?.items || [];
  const pageSize = Math.max(1, comparison?.pageSize || 5);
  const [pageNumber, setPageNumber] = useState(1);
  const [pricingFilters, setPricingFilters] = useState(emptyPricingFilters);
  const panelFilterLabels = pricingFilterLabels();
  const filterOptions = pricingFilterOptionsFromItems(items, () => []);
  const filteredItems = hasActivePricingFilters(pricingFilters)
    ? items.filter((item) => pricingItemMatchesFilters(item, pricingFilters))
    : items;

  useEffect(() => {
    setPageNumber(1);
  }, [comparison?.sourceRegion, comparison?.targetRegion, comparison?.returnedItems, comparison?.totalItems]);

  useEffect(() => {
    setPageNumber(1);
  }, [pricingFilters.productName, pricingFilters.skuName, pricingFilters.meterName]);

  useEffect(() => {
    setPricingFilters(emptyPricingFilters);
  }, [comparison?.sourceRegion, comparison?.targetRegion, comparison?.returnedItems, comparison?.totalItems]);

  if (!items.length) {
    return (
      <div className={styles.pricingPanel}>
        <div className={styles.pricingPanelMeta}>
          <Subtitle1>Cost comparison</Subtitle1>
          <Caption1>{formatPricingSummary(summary) || 'Pricing: unavailable'}</Caption1>
        </div>
      </div>
    );
  }

  const totalPages = Math.max(1, Math.ceil(filteredItems.length / pageSize));
  const safePage = Math.min(pageNumber, totalPages);
  const visibleItems = filteredItems.slice((safePage - 1) * pageSize, safePage * pageSize);
  const shownCount = Math.min(filteredItems.length, safePage * pageSize);

  return (
    <div className={styles.pricingPanel}>
      <div className={styles.pricingPanelHeader}>
        <div className={styles.pricingPanelMeta}>
          <Subtitle1>Cost comparison</Subtitle1>
          <Caption1>
            Comparing {comparison?.returnedItems || items.length} meter{(comparison?.returnedItems || items.length) === 1 ? '' : 's'} across {sourceRegion} and {targetRegion}
          </Caption1>
          {comparison?.truncated ? (
            <Caption1>Showing the first {comparison?.returnedItems || items.length} matched meters from {comparison?.totalItems || items.length} total.</Caption1>
          ) : null}
        </div>
        <Badge appearance="tint" color="brand">{filteredItems.length} of {comparison?.totalItems || items.length} meters</Badge>
      </div>

      <PricingFilterBar
        filters={pricingFilters}
        setFilters={setPricingFilters}
        filteredCount={filteredItems.length}
        totalCount={items.length}
        itemLabel="pricing meter"
        filterOptions={filterOptions}
        filterLabels={panelFilterLabels}
        styles={styles}
      />

      {filteredItems.length ? (
      <div className={styles.pricingTable}>
        <div className={styles.pricingHeader}>
          <div className={styles.pricingHeaderCell}>Meter</div>
          <div className={styles.pricingHeaderCell}>{sourceRegion}</div>
          <div className={styles.pricingHeaderCell}>{targetRegion}</div>
          <div className={styles.pricingHeaderCell}>Delta</div>
        </div>
        {visibleItems.map((item) => {
          const sourceTone = pricingCellTone(item, 'source', sourceRegion, targetRegion);
          const targetTone = pricingCellTone(item, 'target', sourceRegion, targetRegion);
          const deltaInfo = pricingDeltaInfo(item, sourceRegion, targetRegion);
          const sourceToneClass = sourceTone.tone === 'positive'
            ? styles.pricingDeltaNegative
            : sourceTone.tone === 'negative'
              ? styles.pricingDeltaPositive
              : styles.pricingDeltaNeutral;
          const targetToneClass = targetTone.tone === 'positive'
            ? styles.pricingDeltaNegative
            : targetTone.tone === 'negative'
              ? styles.pricingDeltaPositive
              : styles.pricingDeltaNeutral;
          const deltaToneClass = deltaInfo.tone === 'positive'
            ? styles.pricingDeltaNegative
            : deltaInfo.tone === 'negative'
              ? styles.pricingDeltaPositive
              : styles.pricingDeltaNeutral;

          return (
            <div key={item.key} className={styles.pricingRow}>
              <div className={`${styles.pricingCell} ${styles.pricingMeterCell}`}>
                <div>{item.label}</div>
                <Caption1>{item.productName || item.skuName || item.meterName || 'Meter'}</Caption1>
              </div>
              <div className={styles.pricingCell}>
                <div className={styles.pricingValue}>
                  <div>{formatPriceValueWithContext(item.sourcePrice, item.currencyCode || comparison?.currencyCode, item.unitOfMeasure, { priceType: item?.sourcePriceType || item?.targetPriceType, reservationTerm: item?.sourceReservationTerm || item?.targetReservationTerm })}</div>
                  <Caption1 className={sourceToneClass}>{sourceTone.label}</Caption1>
                </div>
              </div>
              <div className={styles.pricingCell}>
                <div className={styles.pricingValue}>
                  <div>{formatPriceValueWithContext(item.targetPrice, item.currencyCode || comparison?.currencyCode, item.unitOfMeasure, { priceType: item?.targetPriceType || item?.sourcePriceType, reservationTerm: item?.targetReservationTerm || item?.sourceReservationTerm })}</div>
                  <Caption1 className={targetToneClass}>{targetTone.label}</Caption1>
                </div>
              </div>
              <div className={styles.pricingCell}>
                <div className={styles.pricingValue}>
                  <div className={deltaToneClass}>{deltaInfo.label}</div>
                  <Caption1>{deltaInfo.detail}</Caption1>
                </div>
              </div>
            </div>
          );
        })}
      </div>
      ) : <div className={styles.emptyBlock}>No pricing meters match the current product, SKU, and meter filters.</div>}

      {filteredItems.length && totalPages > 1 ? (
        <div className={styles.pager}>
          <Caption1>Showing {shownCount - visibleItems.length + 1}-{shownCount} of {filteredItems.length}</Caption1>
          <div className={styles.pagerActions}>
            <Button
              appearance="subtle"
              icon={<ChevronLeft20Regular />}
              onClick={() => setPageNumber((current) => Math.max(1, current - 1))}
              disabled={safePage <= 1}
            >
              Previous
            </Button>
            <Caption1>Page {safePage} of {totalPages}</Caption1>
            <Button
              appearance="subtle"
              icon={<ChevronRight20Regular />}
              iconPosition="after"
              onClick={() => setPageNumber((current) => Math.min(totalPages, current + 1))}
              disabled={safePage >= totalPages}
            >
              Next
            </Button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function tryParseDetails(raw) {
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function healthTone(healthStatus) {
  const normalized = `${healthStatus || ''}`.toLowerCase();
  if (normalized.includes('success') || normalized.includes('healthy') || normalized.includes('complete') || normalized === 'ok') {
    return 'success';
  }
  if (normalized.includes('running') || normalized.includes('refresh')) {
    return 'warning';
  }
  if (normalized.includes('fail') || normalized.includes('error')) {
    return 'danger';
  }
  return 'neutral';
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) {
    const payload = await response.json().catch(() => ({ error: response.statusText }));
    throw new Error(payload.error || 'Request failed');
  }
  return response.json();
}

function normalizeRequestValue(value) {
  return `${value || ''}`.trim().toLowerCase();
}

function parseRunStartedAt(run) {
  const timestamp = Date.parse(`${run?.started_at || ''}`);
  return Number.isNaN(timestamp) ? 0 : timestamp;
}

function runMatchesRefreshRequest(run, requestBody, submittedAtMs) {
  const submitBufferMs = 120000;
  if (parseRunStartedAt(run) + submitBufferMs < submittedAtMs) {
    return false;
  }

  if (normalizeRequestValue(run?.comparison_mode) !== normalizeRequestValue(requestBody?.comparisonMode)) {
    return false;
  }
  if (normalizeRequestValue(run?.source_region) !== normalizeRequestValue(requestBody?.sourceRegion)) {
    return false;
  }
  if (normalizeRequestValue(run?.target_region) !== normalizeRequestValue(requestBody?.targetRegion)) {
    return false;
  }

  const requestedSubscriptionId = normalizeRequestValue(requestBody?.subscriptionId);
  if (requestedSubscriptionId && normalizeRequestValue(run?.subscription_id) !== requestedSubscriptionId) {
    return false;
  }

  return true;
}

function waitForDuration(ms) {
  return new Promise((resolve) => {
    window.setTimeout(resolve, ms);
  });
}

export default function App() {
  const styles = useStyles();
  const resultsTableId = useId('results-table');
  const [themeMode, setThemeMode] = useState(() => {
    if (typeof window === 'undefined') {
      return 'light';
    }
    const stored = window.localStorage.getItem('aca-theme-mode');
    if (stored === 'light' || stored === 'dark') {
      return stored;
    }
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  });
  const [session, setSession] = useState(null);
  const [runs, setRuns] = useState([]);
  const [results, setResults] = useState([]);
  const [resultsMetadata, setResultsMetadata] = useState({});
  const [selectedRunId, setSelectedRunId] = useState('');
  const [latestRunId, setLatestRunId] = useState('');
  const [health, setHealth] = useState({ status: 'Checking', latestRunStatus: 'Checking' });
  const [error, setError] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isInitializing, setIsInitializing] = useState(true);
  const [formValues, setFormValues] = useState({
    comparisonMode: 'inventory',
    sourceRegion: 'canadacentral',
    targetRegion: 'eastus',
    subscriptionId: '',
  });
  const [filters, setFilters] = useState({
    searchText: '',
    family: 'all',
    status: 'all',
    identityMode: 'all',
    identitySource: 'all',
    triageFocus: 'all',
  });
  const [searchInput, setSearchInput] = useState('');
  const [activeView, setActiveView] = useState('overview');
  const [pageNumber, setPageNumber] = useState(1);

  const deferredSearchText = useDeferredValue(searchInput);
  const indexedResults = useMemo(
    () => results.map((item) => {
      const parsedDetails = tryParseDetails(item?.details_json);
      const serviceIdentity = parsedDetails?.serviceIdentity || null;
      const searchValues = [
        item.service,
        item.provider,
        item.notes,
        serviceIdentity?.canonicalServiceName,
        serviceIdentity?.canonicalServiceId,
        serviceIdentity?.canonicalFamily,
        serviceIdentity?.matchedServiceKey,
        serviceIdentity?.providerNamespace,
        serviceIdentity?.identitySource,
        serviceIdentity?.matchStrategy,
        ...(serviceIdentity?.provenance?.serviceNames || []),
        ...(serviceIdentity?.provenance?.serviceFamilies || []),
        ...(serviceIdentity?.provenance?.productNames || []),
        ...(serviceIdentity?.provenance?.searchKeywords || []),
      ]
        .filter(Boolean)
        .map((value) => `${value}`.toLowerCase());

      return {
        ...item,
        _details: parsedDetails,
        _serviceIdentity: serviceIdentity,
        _searchValues: searchValues,
        _searchIndex: searchValues.join('\n'),
      };
    }),
    [results],
  );

  const comparisonModes = session?.comparisonModes || [];
  const regions = session?.regions || [];
  const currentRun = runs.find((run) => run.RowKey === selectedRunId) || runs.find((run) => run.RowKey === latestRunId) || null;
  const hasActiveFilters = Boolean(searchInput.trim()) || filters.family !== 'all' || filters.status !== 'all' || filters.identityMode !== 'all' || filters.identitySource !== 'all' || filters.triageFocus !== 'all';
  const coverageDiagnostics = resultsMetadata?.coverageDiagnostics || null;
  const identitySourceEntries = Object.entries(coverageDiagnostics?.identitySourceCounts || {}).sort((left, right) => {
    if (right[1] !== left[1]) {
      return right[1] - left[1];
    }
    return left[0].localeCompare(right[0]);
  });

  const text = deferredSearchText.trim().toLowerCase();
  const selectedMode = comparisonModes.find((option) => option.value === formValues.comparisonMode) || null;
  const signedInLabel = session?.user?.name || 'Loading account';
  const subscriptionSummary = formValues.subscriptionId.trim() ? 'Using a subscription override for this comparison.' : 'Using your signed-in subscription by default.';
  const latestRunLabel = currentRun ? formatRunLabel(currentRun) : latestRunId || 'No comparisons started yet';
  const serviceFamilyCount = new Set(indexedResults.map((item) => resultCanonicalFamily(item)).filter(Boolean)).size;
  const summaryMatchesSelection = Boolean(
    currentRun
    && `${currentRun.source_region || ''}`.trim().toLowerCase() === `${formValues.sourceRegion || ''}`.trim().toLowerCase()
    && `${currentRun.target_region || ''}`.trim().toLowerCase() === `${formValues.targetRegion || ''}`.trim().toLowerCase()
    && `${currentRun.comparison_mode || ''}`.trim().toLowerCase() === `${formValues.comparisonMode || ''}`.trim().toLowerCase(),
  );
  const sourceRegionSummaryLabel = formValues.sourceRegion;
  const targetRegionSummaryLabel = formValues.targetRegion;
  const sourceRegionAzSummary = summaryMatchesSelection ? regionAzSummaryValue(indexedResults, 'sourceRegion') : 'Run comparison to verify AZ posture';
  const targetRegionAzSummary = summaryMatchesSelection ? regionAzSummaryValue(indexedResults, 'targetRegion') : 'Run comparison to verify AZ posture';
  const serviceFamilySummary = summaryMatchesSelection
    ? (serviceFamilyCount ? `${serviceFamilyCount} in the current run` : 'Available after the first completed comparison.')
    : 'Run the selected comparison to load family coverage.';
  const baseFilteredResults = indexedResults.filter((item) => {
    if (filters.family !== 'all' && !resultFamilyValues(item).includes(filters.family)) {
      return false;
    }
    if (filters.status !== 'all' && item.availability !== filters.status) {
      return false;
    }
    if (filters.identityMode === 'fallback' && !resultHasIdentityFallback(item)) {
      return false;
    }
    if (filters.identityMode === 'matched' && resultHasIdentityFallback(item)) {
      return false;
    }
    const identitySource = resultServiceIdentity(item)?.identitySource || 'unknown';
    if (filters.identitySource !== 'all' && identitySource !== filters.identitySource) {
      return false;
    }
    if (!text) {
      return true;
    }

    return resultSearchIndex(item).includes(text);
  });

  const filteredResults = baseFilteredResults
    .filter((item) => filters.triageFocus === 'all' || resultTriageBucket(item) === filters.triageFocus)
    .sort((left, right) => {
      const bucketDelta = triageRank(resultTriageBucket(left)) - triageRank(resultTriageBucket(right));
      if (bucketDelta !== 0) {
        return bucketDelta;
      }
      return `${left.service || ''}`.localeCompare(`${right.service || ''}`);
    });

  const triageSummary = {
    regionGap: baseFilteredResults.filter((item) => resultTriageBucket(item) === 'region-gap').length,
    identityReview: baseFilteredResults.filter((item) => resultTriageBucket(item) === 'identity-review').length,
    pricingFollowUp: baseFilteredResults.filter((item) => resultTriageBucket(item) === 'pricing-follow-up').length,
    moveReady: baseFilteredResults.filter((item) => resultTriageBucket(item) === 'move-ready').length,
  };

  const familyOptions = ['all', ...new Set(indexedResults.flatMap((item) => resultFamilyValues(item)).filter(Boolean))].sort();
  const statusOptions = ['all', ...new Set(indexedResults.map((item) => item.availability).filter(Boolean))].sort();
  const identitySourceOptions = ['all', ...new Set(indexedResults.map((item) => resultServiceIdentity(item)?.identitySource || '').filter(Boolean))].sort();

  const summary = !filteredResults.length
    ? emptySummary
    : {
        total: filteredResults.length,
        matching: filteredResults.filter((item) => resultIsMoveReady(item)).length,
        gaps: filteredResults.filter((item) => resultHasRegionGap(item)).length,
        identityGaps: filteredResults.filter((item) => resultHasIdentityFallback(item)).length,
        families: new Set(filteredResults.map((item) => resultCanonicalFamily(item)).filter(Boolean)).size,
      };

  const totalPages = Math.max(1, Math.ceil(filteredResults.length / pageSize));
  const safePageNumber = Math.min(pageNumber, totalPages);
  const pagedResults = filteredResults.slice((safePageNumber - 1) * pageSize, safePageNumber * pageSize);
  const hasStructuredDetails = indexedResults.some((item) => Boolean(item?._details?.layout));
  const activeTheme = themeMode === 'dark' ? webDarkTheme : webLightTheme;
  const themeVars = buildThemeVars(themeMode);

  useEffect(() => {
    if (typeof window !== 'undefined') {
      window.localStorage.setItem('aca-theme-mode', themeMode);
    }
  }, [themeMode]);

  useEffect(() => {
    if (pageNumber !== safePageNumber) {
      setPageNumber(safePageNumber);
    }
  }, [pageNumber, safePageNumber]);

  useEffect(() => {
    setSearchInput(filters.searchText);
  }, [filters.searchText]);

  useEffect(() => {
    setPageNumber(1);
  }, [searchInput, filters.family, filters.status, filters.identityMode, filters.identitySource, filters.triageFocus, selectedRunId, results.length]);

  async function refreshHealth() {
    const payload = await fetchJson('/api/health');
    setHealth(payload);
  }

  async function loadRuns() {
    const payload = await fetchJson('/api/runs?limit=20');
    setRuns(payload.items || []);
  }

  async function loadComparisons(runId = '') {
    const query = new URLSearchParams();
    if (runId) {
      query.set('runId', runId);
    }

    const payload = await fetchJson(`/api/comparisons?${query.toString()}`);
    startTransition(() => {
      const resolvedRunId = runId || payload.metadata?.latestRunId || '';
      setSelectedRunId(resolvedRunId);
      setLatestRunId(payload.metadata?.latestRunId || '');
      setResultsMetadata(payload.metadata || {});
      setResults(payload.items || []);
    });
  }

  async function recoverCompletedRefreshRun(requestBody, submittedAtMs) {
    for (let attempt = 0; attempt < 6; attempt += 1) {
      try {
        const payload = await fetchJson('/api/runs?limit=20');
        const matchingRuns = (payload.items || []).filter((run) => runMatchesRefreshRequest(run, requestBody, submittedAtMs));
        const completedRun = matchingRuns.find((run) => normalizeRequestValue(run?.status) === 'completed' && run?.RowKey);
        if (completedRun) {
          return completedRun;
        }
      } catch {
        // Ignore recovery polling errors and preserve the original refresh failure.
      }

      if (attempt < 5) {
        await waitForDuration(3000);
      }
    }

    return null;
  }

  async function initialize() {
    setIsInitializing(true);
    setError('');

    try {
      const sessionPayload = await fetchJson('/api/session');
      setSession(sessionPayload);
      setFormValues((current) => ({
        ...current,
        comparisonMode: sessionPayload.defaults?.comparisonMode || current.comparisonMode,
        sourceRegion: sessionPayload.defaults?.sourceRegion || current.sourceRegion,
        targetRegion: sessionPayload.defaults?.targetRegion || current.targetRegion,
      }));

      await Promise.all([refreshHealth(), loadRuns(), loadComparisons()]);
    } catch (loadError) {
      setError(loadError.message);
    } finally {
      setIsInitializing(false);
    }
  }

  useEffect(() => {
    initialize();
  }, []);

  async function handleSubmit(event) {
    event.preventDefault();
    setIsSubmitting(true);
    setError('');
    const submittedAtMs = Date.now();

    const body = {
      comparisonMode: formValues.comparisonMode,
      sourceRegion: formValues.sourceRegion,
      targetRegion: formValues.targetRegion,
    };

    if (formValues.subscriptionId.trim()) {
      body.subscriptionId = formValues.subscriptionId.trim();
    }

    try {
      const payload = await fetchJson('/api/refresh', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });

      await Promise.all([loadRuns(), loadComparisons(payload.runId), refreshHealth()]);
      setActiveView('results');
    } catch (submitError) {
      const recoveredRun = await recoverCompletedRefreshRun(body, submittedAtMs);
      if (recoveredRun?.RowKey) {
        await Promise.all([loadRuns(), loadComparisons(recoveredRun.RowKey), refreshHealth()]);
        setActiveView('results');
        return;
      }

      setError(submitError.message);
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleRunSelection(runId) {
    setError('');
    try {
      await loadComparisons(runId);
      setActiveView('results');
    } catch (loadError) {
      setError(loadError.message);
    }
  }

  function renderStatusBadge(statusText, appearance = 'filled', sourceRegion = '', targetRegion = '') {
    const tone = healthTone(statusText);
    const color = tone === 'success' ? 'success' : tone === 'danger' ? 'danger' : tone === 'warning' ? 'warning' : 'informative';
    const label = sourceRegion || targetRegion
      ? formatAvailabilityLabel(statusText, sourceRegion, targetRegion, false)
      : (statusText || 'Unknown');
    return <Badge appearance={appearance} color={color}>{label}</Badge>;
  }

  function renderHealthSummary() {
    return (
      <>
        {renderStatusBadge(health.status, 'filled')}
        {health.latestRunStatus ? renderStatusBadge(health.latestRunStatus, 'tint') : null}
      </>
    );
  }

  function renderErrorBar() {
    if (!error) {
      return null;
    }

    return (
      <MessageBar intent="error">
        <MessageBarBody>{error}</MessageBarBody>
      </MessageBar>
    );
  }

  function renderOverview() {
    return (
      <div className={styles.splitLayout}>
        <Card className={`${styles.sectionCard} ${styles.primaryOverviewCard}`}>
          <div className={styles.sectionHeader}>
            <div className={styles.sectionMeta}>
              <Caption1>Compare regions</Caption1>
              <Title1>Start a regional comparison</Title1>
              <Body1>Choose the scope, pick two regions, and send the comparison straight to Results.</Body1>
            </div>
            <Badge appearance="filled" color="brand">Ready</Badge>
          </div>

          <div className={styles.overviewInset}>
            <Subtitle1>{selectedMode?.label || `${formatModeLabel(formValues.comparisonMode)} comparison`}</Subtitle1>
            <Caption1>{modeSupportText(formValues.comparisonMode)}</Caption1>
          </div>

          <form className={styles.stack} onSubmit={handleSubmit}>
            <div className={styles.formGrid}>
              <Field label="Comparison mode">
                <Dropdown
                  value={comparisonModes.find((option) => option.value === formValues.comparisonMode)?.label || ''}
                  selectedOptions={[formValues.comparisonMode]}
                  onOptionSelect={(_, data) => setFormValues((current) => ({ ...current, comparisonMode: data.optionValue || current.comparisonMode }))}
                >
                  {comparisonModes.map((option) => (
                    <Option key={option.value} value={option.value} text={option.label}>
                      {option.label}
                    </Option>
                  ))}
                </Dropdown>
              </Field>

              <Field label="Source region">
                <Dropdown
                  value={formValues.sourceRegion}
                  selectedOptions={[formValues.sourceRegion]}
                  onOptionSelect={(_, data) => setFormValues((current) => ({ ...current, sourceRegion: data.optionValue || current.sourceRegion }))}
                >
                  {regions.map((region) => (
                    <Option key={region} value={region} text={region}>
                      {region}
                    </Option>
                  ))}
                </Dropdown>
              </Field>

              <Field label="Target region">
                <Dropdown
                  value={formValues.targetRegion}
                  selectedOptions={[formValues.targetRegion]}
                  onOptionSelect={(_, data) => setFormValues((current) => ({ ...current, targetRegion: data.optionValue || current.targetRegion }))}
                >
                  {regions.map((region) => (
                    <Option key={region} value={region} text={region}>
                      {region}
                    </Option>
                  ))}
                </Dropdown>
              </Field>

              <Field className={styles.wideField} label="Subscription scope">
                <Input
                  value={formValues.subscriptionId}
                  placeholder="Leave blank to use your current subscription"
                  onChange={(_, data) => setFormValues((current) => ({ ...current, subscriptionId: data.value }))}
                />
              </Field>
            </div>

            <div className={styles.actionRow}>
              <Button appearance="primary" icon={<PlayCircle24Regular />} type="submit" disabled={isSubmitting}>
                {isSubmitting ? 'Running comparison…' : 'Run comparison'}
              </Button>
              <Caption1>We&apos;ll take you straight to Results so you can review region gaps, fallback identities, and pricing follow-up in that order.</Caption1>
            </div>

            <div className={styles.overviewInset}>
              <Subtitle1>What happens next</Subtitle1>
              <Caption1>
                Results opens on the newest run and surfaces the highest-action rows first. Start with region gaps, then confirm fallback identities, then review pricing detail where needed.
              </Caption1>
            </div>

            {renderErrorBar()}
          </form>
        </Card>

        <div className={styles.stack}>
          <Card className={styles.sectionCard}>
            <div className={styles.sectionMeta}>
              <Caption1>What you&apos;ll get</Caption1>
              <Subtitle1>Comparison output</Subtitle1>
            </div>
            <ul className={styles.overviewList}>
              <li>See which services are blocked in the target region before you spend time on clean matches.</li>
              <li>Review fallback identity rows separately from pricing and capability detail.</li>
              <li>Return to the latest run from Results and Runs without restarting the comparison.</li>
            </ul>
          </Card>

          <Card className={styles.sectionCard}>
            <div className={styles.sectionMeta}>
              <Caption1>Regional summary</Caption1>
              <Subtitle1>Scope, families, and AZ posture</Subtitle1>
            </div>
            <div className={styles.overviewKeyGrid}>
              <div className={styles.overviewKeyItem}>
                <Caption1>Source region</Caption1>
                <Body1>{sourceRegionSummaryLabel}</Body1>
                <Badge appearance="tint" color={regionAzSummaryTone(sourceRegionAzSummary)}>{sourceRegionAzSummary}</Badge>
              </div>
              <div className={styles.overviewKeyItem}>
                <Caption1>Target region</Caption1>
                <Body1>{targetRegionSummaryLabel}</Body1>
                <Badge appearance="tint" color={regionAzSummaryTone(targetRegionAzSummary)}>{targetRegionAzSummary}</Badge>
              </div>
              <div className={styles.overviewKeyItem}>
                <Caption1>Service families</Caption1>
                <Body1>{serviceFamilySummary}</Body1>
              </div>
              <div className={styles.overviewKeyItem}>
                <Caption1>Signed in</Caption1>
                <Body1>{signedInLabel}</Body1>
              </div>
              <div className={styles.overviewKeyItem}>
                <Caption1>Subscription</Caption1>
                <Body1>{subscriptionSummary}</Body1>
              </div>
              <div className={styles.overviewKeyItem}>
                <Caption1>Latest run</Caption1>
                <Body1>{latestRunLabel}</Body1>
              </div>
            </div>
          </Card>

          <Card className={styles.sectionCard}>
            <div className={styles.sectionMeta}>
              <Caption1>System status</Caption1>
              <Subtitle1>Ready to compare</Subtitle1>
            </div>
            <div className={styles.actionRow}>
              {isInitializing ? <Spinner size="tiny" label="Refreshing" /> : null}
              {renderHealthSummary()}
            </div>
            <Caption1>The app is connected and ready for your next comparison. Use the regional summary above to sanity-check family coverage and AZ posture before you run again.</Caption1>
          </Card>
        </div>
      </div>
    );
  }

  function renderRunsView() {
    return (
      <Card className={styles.sectionCard}>
        <div className={styles.sectionHeader}>
          <div className={styles.sectionMeta}>
            <Caption1>Run history</Caption1>
            <Title1>Recent runs</Title1>
            <Body1>Open any previous run without changing the current form.</Body1>
          </div>
          <Button appearance="secondary" icon={<ArrowClockwise20Regular />} onClick={() => loadRuns().catch((loadError) => setError(loadError.message))}>
            Refresh runs
          </Button>
        </div>

        <div className={styles.runList}>
          {runs.length ? runs.map((run) => (
            <button
              key={run.RowKey}
              type="button"
              className={`${styles.runButton} ${selectedRunId === run.RowKey ? styles.runButtonSelected : ''}`}
              onClick={() => handleRunSelection(run.RowKey)}
            >
              <div className={styles.runButtonAccent} style={{ backgroundColor: `${run.comparison_mode || ''}`.toLowerCase() === 'inventory' ? tokens.colorPaletteGreenBorder2 : tokens.colorPaletteBlueBorderActive }} />
              <div className={styles.runButtonContent}>
                <div className={styles.sectionHeader}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    {runModeIcon(run.comparison_mode)}
                    <Subtitle1>{formatRunLabel(run)}</Subtitle1>
                  </div>
                  {renderStatusBadge(run.status, selectedRunId === run.RowKey ? 'filled' : 'tint')}
                </div>
                <Caption1 className={styles.runMeta}>{formatRunMeta(run)}</Caption1>
                <Caption1 className={styles.runMeta}>Run ID {run.RowKey}</Caption1>
              </div>
            </button>
          )) : (
            <div className={styles.emptyBlock}>No runs are available yet. Start a comparison from the overview tab.</div>
          )}
        </div>

        {renderErrorBar()}
      </Card>
    );
  }

  function renderResultsView() {
    const selectedRunBadge = selectedRunId || latestRunId;
    const runTitle = currentRun
      ? `${currentRun.source_region || 'source'} -> ${currentRun.target_region || 'target'}`
      : latestRunId
        ? `Latest run ${latestRunId}`
        : 'Comparison results';
    const runSubtitle = currentRun
      ? `${formatModeLabel(currentRun.comparison_mode)} • ${currentRun.record_count || results.length} services • ${currentRun.status || 'unknown status'}`
      : 'Filter and review the current result set.';
    const triageCards = [
      {
        key: 'region-gap',
        label: 'Region gaps',
        count: triageSummary.regionGap,
        description: 'Services that do not carry cleanly into the target region.',
      },
      {
        key: 'identity-review',
        label: 'Identity review',
        count: triageSummary.identityReview,
        description: 'Rows that still depend on fallback identity resolution.',
      },
      {
        key: 'pricing-follow-up',
        label: 'Pricing follow-up',
        count: triageSummary.pricingFollowUp,
        description: 'Services that still need clearer regional pricing evidence.',
      },
      {
        key: 'move-ready',
        label: 'Move-ready',
        count: triageSummary.moveReady,
        description: 'Rows with clean alignment and no immediate follow-up signal.',
      },
    ];

    return (
      <Card className={styles.sectionCard}>
        <div className={styles.sectionHeader}>
          <div className={styles.runHeadline}>
            <Caption1>Results</Caption1>
            <Title1 id={resultsTableId}>Comparison results</Title1>
            <Subtitle1>{runTitle}</Subtitle1>
            <Body1 className={styles.runSubhead}>{runSubtitle}</Body1>
          </div>
          {selectedRunBadge ? <Badge appearance="tint" color="brand">Run {selectedRunBadge}</Badge> : null}
        </div>

        <div className={styles.triageGrid}>
          {triageCards.map((card) => {
            const isActive = filters.triageFocus === card.key;
            return (
              <div key={card.key} className={`${styles.triageCard} ${isActive ? styles.triageCardActive : ''}`}>
                <Caption1>{card.label}</Caption1>
                <div className={styles.triageCount}>{card.count}</div>
                <Body1 className={styles.triageDescription}>{card.description}</Body1>
                <div className={styles.actionRow}>
                  <Button
                    appearance={isActive ? 'primary' : 'secondary'}
                    size="small"
                    onClick={() => setFilters((current) => ({ ...current, triageFocus: isActive ? 'all' : card.key }))}
                  >
                    {isActive ? 'Show all results' : `Focus ${card.label.toLowerCase()}`}
                  </Button>
                </div>
              </div>
            );
          })}
        </div>

        <div className={styles.toolbar}>
          <Field label="Search">
            <Input
              value={searchInput}
              placeholder="Search services, canonical IDs, providers, or notes"
              onChange={(_, data) => {
                const nextValue = data.value;
                setSearchInput(nextValue);
                startTransition(() => {
                  setFilters((current) => ({ ...current, searchText: nextValue }));
                });
              }}
            />
          </Field>

          <Field label="Family">
            <Dropdown
              value={filters.family === 'all' ? 'All families' : formatFamilyLabel(filters.family)}
              selectedOptions={[filters.family]}
              onOptionSelect={(_, data) => setFilters((current) => ({ ...current, family: data.optionValue || current.family }))}
            >
              {familyOptions.map((family) => (
                <Option key={family} value={family} text={family === 'all' ? 'All families' : formatFamilyLabel(family)}>
                  {family === 'all' ? 'All families' : formatFamilyLabel(family)}
                </Option>
              ))}
            </Dropdown>
          </Field>

          <Field label="Status">
            <Dropdown
              value={formatStatusOptionLabel(filters.status, formValues.sourceRegion, formValues.targetRegion)}
              selectedOptions={[filters.status]}
              onOptionSelect={(_, data) => setFilters((current) => ({ ...current, status: data.optionValue || current.status }))}
            >
              {statusOptions.map((status) => (
                <Option key={status} value={status} text={formatStatusOptionLabel(status, formValues.sourceRegion, formValues.targetRegion)}>
                  {formatStatusOptionLabel(status, formValues.sourceRegion, formValues.targetRegion)}
                </Option>
              ))}
            </Dropdown>
          </Field>

          <Field label="Identity coverage">
            <Dropdown
              value={filters.identityMode === 'all' ? 'All identity rows' : filters.identityMode === 'fallback' ? 'Fallback only' : 'Matched only'}
              selectedOptions={[filters.identityMode]}
              onOptionSelect={(_, data) => setFilters((current) => ({ ...current, identityMode: data.optionValue || current.identityMode }))}
            >
              <Option value="all" text="All identity rows">All identity rows</Option>
              <Option value="fallback" text="Fallback only">Fallback only</Option>
              <Option value="matched" text="Matched only">Matched only</Option>
            </Dropdown>
          </Field>

          <Field label="Identity source">
            <Dropdown
              value={filters.identitySource === 'all' ? 'All identity sources' : formatIdentityLabel(filters.identitySource)}
              selectedOptions={[filters.identitySource]}
              onOptionSelect={(_, data) => setFilters((current) => ({ ...current, identitySource: data.optionValue || current.identitySource }))}
            >
              <Option value="all" text="All identity sources">All identity sources</Option>
              {identitySourceOptions.filter((option) => option !== 'all').map((source) => (
                <Option key={source} value={source} text={formatIdentityLabel(source)}>
                  {formatIdentityLabel(source)}
                </Option>
              ))}
            </Dropdown>
          </Field>

          <div className={styles.toolbarActions}>
            <Button appearance="secondary" onClick={() => {
              setSearchInput('');
              setFilters({ searchText: '', family: 'all', status: 'all', identityMode: 'all', identitySource: 'all', triageFocus: 'all' });
            }}>Clear filters</Button>
          </div>
        </div>

        {renderErrorBar()}

        {coverageDiagnostics?.identityRecordCount ? (
          <div className={styles.metadataBlock}>
            <div className={styles.sectionHeader}>
              <div className={styles.sectionMeta}>
                <Caption1>Coverage diagnostics</Caption1>
                <Subtitle1>Canonical identity coverage</Subtitle1>
              </div>
              <Badge appearance="outline">{coverageDiagnostics.identityRecordCount} identity rows</Badge>
            </div>

            <div className={styles.metricStrip}>
              <div className={styles.metricCard} style={{ backgroundColor: 'var(--app-summary-a)' }}>
                <Caption1>Matched identities</Caption1>
                <Subtitle1>{coverageDiagnostics.matchedCount || 0}</Subtitle1>
              </div>
              <div className={styles.metricCard} style={{ backgroundColor: 'var(--app-summary-c)' }}>
                <Caption1>Fallback identities</Caption1>
                <Subtitle1>{coverageDiagnostics.fallbackCount || 0}</Subtitle1>
              </div>
              <div className={styles.metricCard} style={{ backgroundColor: 'var(--app-summary-d)' }}>
                <Caption1>Canonical services</Caption1>
                <Subtitle1>{coverageDiagnostics.uniqueCanonicalServiceCount || 0}</Subtitle1>
              </div>
            </div>

            <div className={styles.actionRow}>
              <Button appearance="secondary" size="small" onClick={() => setFilters((current) => ({ ...current, identityMode: 'fallback' }))}>
                Show fallback rows
              </Button>
              <Button appearance="subtle" size="small" onClick={() => setFilters((current) => ({ ...current, identityMode: 'all', identitySource: 'all' }))}>
                Clear identity focus
              </Button>
            </div>

            {(coverageDiagnostics.topFallbackProviders?.length || coverageDiagnostics.topFallbackServices?.length) ? (
              <div className={styles.identityGrid}>
                <div className={styles.identityCard}>
                  <Caption1>Top fallback providers</Caption1>
                  {coverageDiagnostics.topFallbackProviders?.length ? (
                    <ul className={styles.detailList}>
                      {coverageDiagnostics.topFallbackProviders.map((item) => (
                        <li key={item.providerNamespace} className={styles.detailItem}>
                          <span className={styles.detailValueMono}>{item.providerNamespace}</span>{' '}({item.count})
                        </li>
                      ))}
                    </ul>
                  ) : <Caption1 className={styles.detailValueSubtle}>No fallback providers in this result set.</Caption1>}
                </div>
                <div className={styles.identityCard}>
                  <Caption1>Top fallback services</Caption1>
                  {coverageDiagnostics.topFallbackServices?.length ? (
                    <ul className={styles.detailList}>
                      {coverageDiagnostics.topFallbackServices.map((item) => (
                        <li key={item.canonicalServiceId || item.canonicalServiceName} className={styles.detailItem}>
                          <span className={styles.detailValueStrong}>{item.canonicalServiceName || item.canonicalServiceId}</span>
                          {item.canonicalServiceId ? <span className={styles.detailValueMono}> {item.canonicalServiceId}</span> : null}
                          {' '}({item.count})
                        </li>
                      ))}
                    </ul>
                  ) : <Caption1 className={styles.detailValueSubtle}>No fallback services in this result set.</Caption1>}
                </div>
                <div className={styles.identityCard}>
                  <Caption1>Diagnostic totals</Caption1>
                  <div className={styles.detailValueStrong}>{coverageDiagnostics.diagnosticCount || 0}</div>
                  <Caption1 className={styles.detailValueSubtle}>Detailed identity diagnostics attached to fallback rows</Caption1>
                  <Caption1 className={styles.detailValueSubtle}>{coverageDiagnostics.uniqueCanonicalFamilyCount || 0} canonical families represented</Caption1>
                </div>
                <div className={styles.identityCard}>
                  <Caption1>Identity sources</Caption1>
                  {identitySourceEntries.length ? (
                    <ul className={styles.detailList}>
                      {identitySourceEntries.map(([source, count]) => (
                        <li key={source} className={styles.detailItem}>
                          <span className={styles.detailValueStrong}>{formatIdentityLabel(source) || source}</span>{' '}({count})
                        </li>
                      ))}
                    </ul>
                  ) : <Caption1 className={styles.detailValueSubtle}>Identity source counts are not available for this result set.</Caption1>}
                </div>
              </div>
            ) : null}
          </div>
        ) : null}

        {hasStructuredDetails ? (
          <div className={styles.resultCardList}>
            {pagedResults.length ? pagedResults.map((row) => {
              const details = row._details || tryParseDetails(row.details_json);
              const sections = details?.sections || [];
              const inlinePricingSummary = details?.pricingMatchSummary || formatPricingSummary(details?.pricingSummary) || 'Inline pricing shown in the breakdown rows where a retail match exists.';
              const pricingText = (details?.layout === 'family-breakdown' || details?.layout === 'sku-breakdown')
                ? inlinePricingSummary
                : pricingDisplayText(details?.pricingSummary, details?.pricingComparison);
              const summaryStats = details?.summary;
              const metricCards = details?.metricCards || (summaryStats ? [
                { label: 'Source metadata types', value: summaryStats.sourceCount },
                { label: 'Matched curated capabilities', value: summaryStats.matchedCapabilityCount ?? summaryStats.sharedCount },
                { label: 'Capability differences', value: summaryStats.differentCapabilityCount ?? summaryStats.sourceOnlyCount + summaryStats.targetOnlyCount },
                { label: 'Target metadata types', value: summaryStats.targetCount },
              ] : []);
              const curated = details?.curated;
              const surface = statusSurface(row.availability, themeMode);
              const expandedSections = curated?.expandedCapabilities || [];
              const triageBucket = resultTriageBucket(row);
              const summaryText = triageSummaryLabel(triageBucket);
              const compactPricingText = compactPricingSummary(details);
              const showInlinePricingTable = details?.layout === 'family-breakdown' || details?.layout === 'sku-breakdown';
              const serviceIdentity = details?.serviceIdentity;
              const aliasText = identityAliasText(serviceIdentity);
              const usesFallbackIdentity = serviceIdentity?.isFallbackIdentity || serviceIdentity?.matched === false;
              const identityDiagnostics = serviceIdentity?.diagnostics || [];

              return (
                <details
                  key={row.row_key || `${row.provider}-${row.service}-${row.source_region}-${row.target_region}`}
                  className={styles.resultDetails}
                  style={{ borderLeft: `6px solid ${surface.borderColor}`, backgroundColor: surface.backgroundColor }}
                >
                  <summary className={styles.resultSummary}>
                    <div className={styles.resultSummaryGrid}>
                      <div className={styles.resultSummaryMeta}>
                        <Subtitle1>{row.service}</Subtitle1>
                        <div className={styles.resultTagRow}>
                          {renderStatusBadge(row.availability, 'filled', row.source_region, row.target_region)}
                          <Badge appearance="tint" color="brand">{formatFamilyLabel(resultCanonicalFamily(row))}</Badge>
                          {serviceIdentity?.isFallbackIdentity || serviceIdentity?.matched === false ? <Badge appearance="filled" color="warning">Fallback identity</Badge> : null}
                          <Badge appearance="outline" className={styles.resultMetaBadge}>{row.provider}</Badge>
                        </div>
                        <Caption1 className={styles.resultSummaryLead}>{summaryText}</Caption1>
                        {compactPricingText ? <Caption1>{compactPricingText}</Caption1> : null}
                      </div>
                      <Caption1>{row.source_region}{' -> '}{row.target_region}</Caption1>
                    </div>
                  </summary>
                  <div className={styles.resultDetailsBody}>
                    {metricCards.length ? (
                      <div className={styles.metricStrip}>
                        {metricCards.map((card, index) => (
                          <div
                            key={`${row.row_key || row.provider}-${card.label}`}
                            className={styles.metricCard}
                            style={{ backgroundColor: `var(--app-summary-${['a', 'b', 'c', 'd'][index % 4]})` }}
                          >
                            <Caption1>{card.label}</Caption1>
                            <Subtitle1 className={styles.metricCardValue}>{card.value}</Subtitle1>
                          </div>
                        ))}
                      </div>
                    ) : null}

                    {!showInlinePricingTable ? (
                      <PricingComparisonPanel
                        comparison={details?.pricingComparison}
                        summary={details?.pricingSummary}
                        sourceRegion={row.source_region}
                        targetRegion={row.target_region}
                        styles={styles}
                      />
                    ) : null}

                    {serviceIdentity ? (
                      <div className={styles.metadataBlock}>
                        <div className={styles.sectionHeader}>
                          <Subtitle1>Canonical identity</Subtitle1>
                          <div className={styles.identityBadgeRow}>
                            {serviceIdentity.identityConfidence ? <Badge appearance="outline">{formatIdentityLabel(serviceIdentity.identityConfidence)} confidence</Badge> : null}
                            {serviceIdentity.identitySource ? <Badge appearance="tint" color="brand">{formatIdentityLabel(serviceIdentity.identitySource)}</Badge> : null}
                          </div>
                        </div>
                        <div className={styles.identityGrid}>
                          <div className={styles.identityCard}>
                            <Caption1>Canonical service</Caption1>
                            <div className={styles.detailValueStrong}>{serviceIdentity.canonicalServiceName || row.service}</div>
                            {serviceIdentity.canonicalServiceId ? <div className={styles.detailValueMono}>{serviceIdentity.canonicalServiceId}</div> : null}
                            {aliasText ? <Caption1 className={styles.detailValueSubtle}>{aliasText}</Caption1> : null}
                          </div>
                          <div className={styles.identityCard}>
                            <Caption1>Family alignment</Caption1>
                            <div className={styles.detailValueStrong}>{formatFamilyLabel(resultCanonicalFamily(row))}</div>
                            <Caption1 className={styles.detailValueSubtle}>Rendered as {formatFamilyLabel(row.service_family)}</Caption1>
                            {serviceIdentity.matchedServiceKey ? <div className={styles.detailValueMono}>{serviceIdentity.matchedServiceKey}</div> : null}
                          </div>
                          <div className={styles.identityCard}>
                            <Caption1>Resolution status</Caption1>
                            <div className={styles.detailValueStrong}>{usesFallbackIdentity ? 'Fallback identity used' : 'Curated match'}</div>
                            {serviceIdentity.providerNamespace ? <div className={styles.detailValueMono}>{serviceIdentity.providerNamespace}</div> : null}
                            <Caption1 className={styles.detailValueSubtle}>
                              {usesFallbackIdentity
                                ? 'This row needs identity review before you treat it as a clean migration match.'
                                : `Resolved through ${formatIdentityLabel(serviceIdentity.matchStrategy) || 'the current matching flow'}.`}
                            </Caption1>
                          </div>
                        </div>
                        {usesFallbackIdentity ? (
                          <div className={styles.overviewInset}>
                            <Subtitle1>Fallback guidance</Subtitle1>
                            <Caption1>
                              This service is still using fallback identity logic. Review the advanced diagnostics only if you need the raw provider evidence and matching rationale.
                            </Caption1>
                          </div>
                        ) : null}
                        {identityDiagnostics.length ? (
                          <details className={styles.expandedDetails}>
                            <summary className={styles.expandedSummary}>
                              <div className={styles.expandedSummaryMeta}>
                                <div>Advanced identity diagnostics</div>
                                <Caption1>Detailed matching evidence and review notes.</Caption1>
                              </div>
                              <Badge appearance="outline">{identityDiagnostics.length}</Badge>
                            </summary>
                            <div className={styles.expandedBody}>
                              <ul className={styles.detailList}>
                                {identityDiagnostics.map((item) => (
                                  <li key={item.code || item.message} className={styles.detailItem}>
                                    {item.message}
                                  </li>
                                ))}
                              </ul>
                            </div>
                          </details>
                        ) : null}
                      </div>
                    ) : null}

                    {details?.layout === 'service-availability' && curated ? (
                      <>
                        <div className={styles.availabilityPanel}>
                          <Subtitle1>Regional availability</Subtitle1>
                          <Body1>{details?.availabilitySummary?.message || summaryText}</Body1>
                        </div>

                        <div className={styles.availabilityGrid}>
                          <div className={styles.availabilityPanel}>
                            <Caption1>{row.source_region}</Caption1>
                            <Badge appearance="filled" color={curated?.sourceRegion?.serviceAvailable ? 'success' : 'danger'}>
                              {curated?.sourceRegion?.serviceAvailable ? 'Available' : 'Not available'}
                            </Badge>
                            <Caption1>{curated?.sourceRegion?.zoneSupport?.notes || 'No additional regional note.'}</Caption1>
                          </div>
                          <div className={styles.availabilityPanel}>
                            <Caption1>{row.target_region}</Caption1>
                            <Badge appearance="filled" color={curated?.targetRegion?.serviceAvailable ? 'success' : 'danger'}>
                              {curated?.targetRegion?.serviceAvailable ? 'Available' : 'Not available'}
                            </Badge>
                            <Caption1>{curated?.targetRegion?.zoneSupport?.notes || 'No additional regional note.'}</Caption1>
                          </div>
                        </div>

                        <div className={styles.zoneStrip}>
                          <div className={styles.zoneCard}>
                            <div className={styles.zoneCardLabel}>
                              <Caption1>{row.source_region}</Caption1>
                              <Caption1 className={styles.zoneCardMeta}>{curated.sourceRegion?.zoneSupport?.notes || 'Regional zone posture.'}</Caption1>
                            </div>
                            <Badge appearance="filled" color={zoneSupportTone(curated.sourceRegion?.zoneSupport?.mode)}>
                              {curated.sourceRegion?.zoneSupport?.label || 'Unknown'}
                            </Badge>
                            {(curated.sourceRegion?.zoneDependentSkuCount > 0 || (curated.sourceRegion?.effectiveSkuCount != null && curated.sourceRegion?.effectiveSkuCount !== (details?.summary?.sourceCount ?? curated.sourceRegion?.effectiveSkuCount))) && (
                              <div className={styles.zoneCardExtra}>
                                {curated.sourceRegion?.zoneDependentSkuCount > 0 && (
                                  <Badge appearance="tint" color={curated.sourceRegion?.zoneSupport?.mode === 'zone-redundant-unavailable' ? 'danger' : 'informative'}>
                                    {curated.sourceRegion.zoneDependentSkuCount} zone-dependent SKU{curated.sourceRegion.zoneDependentSkuCount !== 1 ? 's' : ''}
                                    {curated.sourceRegion?.zoneSupport?.mode === 'zone-redundant-unavailable' ? ' (effectively unavailable)' : ''}
                                  </Badge>
                                )}
                                {curated.sourceRegion?.effectiveSkuCount != null && curated.sourceRegion?.effectiveSkuCount !== (details?.summary?.sourceCount ?? curated.sourceRegion?.effectiveSkuCount) && (
                                  <Caption1 className={styles.zoneCardMeta}>Effective SKUs: {curated.sourceRegion.effectiveSkuCount} of {details?.summary?.sourceCount}</Caption1>
                                )}
                              </div>
                            )}
                          </div>
                          <div className={styles.zoneCard}>
                            <div className={styles.zoneCardLabel}>
                              <Caption1>{row.target_region}</Caption1>
                              <Caption1 className={styles.zoneCardMeta}>{curated.targetRegion?.zoneSupport?.notes || 'Regional zone posture.'}</Caption1>
                            </div>
                            <Badge appearance="filled" color={zoneSupportTone(curated.targetRegion?.zoneSupport?.mode)}>
                              {curated.targetRegion?.zoneSupport?.label || 'Unknown'}
                            </Badge>
                            {(curated.targetRegion?.zoneDependentSkuCount > 0 || (curated.targetRegion?.effectiveSkuCount != null && curated.targetRegion?.effectiveSkuCount !== (details?.summary?.targetCount ?? curated.targetRegion?.effectiveSkuCount))) && (
                              <div className={styles.zoneCardExtra}>
                                {curated.targetRegion?.zoneDependentSkuCount > 0 && (
                                  <Badge appearance="tint" color={curated.targetRegion?.zoneSupport?.mode === 'zone-redundant-unavailable' ? 'danger' : 'informative'}>
                                    {curated.targetRegion.zoneDependentSkuCount} zone-dependent SKU{curated.targetRegion.zoneDependentSkuCount !== 1 ? 's' : ''}
                                    {curated.targetRegion?.zoneSupport?.mode === 'zone-redundant-unavailable' ? ' (effectively unavailable)' : ''}
                                  </Badge>
                                )}
                                {curated.targetRegion?.effectiveSkuCount != null && curated.targetRegion?.effectiveSkuCount !== (details?.summary?.targetCount ?? curated.targetRegion?.effectiveSkuCount) && (
                                  <Caption1 className={styles.zoneCardMeta}>Effective SKUs: {curated.targetRegion.effectiveSkuCount} of {details?.summary?.targetCount}</Caption1>
                                )}
                              </div>
                            )}
                          </div>
                        </div>
                      </>
                    ) : details?.layout === 'capability-matrix' && curated?.capabilities?.length ? (
                      <>
                        <div className={styles.matrixTable}>
                          <div className={styles.matrixHeader}>
                            <div className={styles.matrixHeaderCell}>Capability</div>
                            <div className={styles.matrixHeaderCell}>{row.source_region}</div>
                            <div className={styles.matrixHeaderCell}>{row.target_region}</div>
                            <div className={styles.matrixHeaderCell}>Priority</div>
                            <div className={styles.matrixHeaderCell}>What this gives you</div>
                          </div>
                          {curated.capabilities
                            .filter((capability) => !hiddenCapabilityKeys.has(`${capability?.key || ''}`))
                            .map((capability) => (
                            <div key={capability.key} className={styles.matrixRow}>
                              <div className={`${styles.matrixCell} ${styles.matrixCapabilityCell}`}>
                                <div>{capability.label}</div>
                                <div className={styles.capabilityMeta}>{capability.key}</div>
                              </div>
                              <div className={styles.matrixCell}>
                                <Badge appearance="filled" color={capabilityBadgeColor(capability.sourceStatus)}>{formatCapabilityStatus(capability.sourceStatus)}</Badge>
                              </div>
                              <div className={styles.matrixCell}>
                                <Badge appearance="filled" color={capabilityBadgeColor(capability.targetStatus)}>{formatCapabilityStatus(capability.targetStatus)}</Badge>
                              </div>
                              <div className={styles.matrixCell}><Badge appearance="tint" color={priorityBadgeColor(capability.importance)}>{capability.importance || 'medium'}</Badge></div>
                              <div className={`${styles.matrixCell} ${styles.matrixNoteCell}`}>{capabilityGuidance(capability, row.source_region, row.target_region)}</div>
                            </div>
                          ))}
                        </div>

                        <div className={styles.zoneStrip}>
                          <div className={styles.zoneCard}>
                            <div className={styles.zoneCardLabel}>
                              <Caption1>{row.source_region}</Caption1>
                              <Caption1 className={styles.zoneCardMeta}>{curated.sourceRegion?.zoneSupport?.notes || 'Regional zone posture.'}</Caption1>
                            </div>
                            <Badge appearance="filled" color={zoneSupportTone(curated.sourceRegion?.zoneSupport?.mode)}>
                              {curated.sourceRegion?.zoneSupport?.label || 'Unknown'}
                            </Badge>
                            {(curated.sourceRegion?.zoneDependentSkuCount > 0 || (curated.sourceRegion?.effectiveSkuCount != null && curated.sourceRegion?.effectiveSkuCount !== (details?.summary?.sourceCount ?? curated.sourceRegion?.effectiveSkuCount))) && (
                              <div className={styles.zoneCardExtra}>
                                {curated.sourceRegion?.zoneDependentSkuCount > 0 && (
                                  <Badge appearance="tint" color={curated.sourceRegion?.zoneSupport?.mode === 'zone-redundant-unavailable' ? 'danger' : 'informative'}>
                                    {curated.sourceRegion.zoneDependentSkuCount} zone-dependent SKU{curated.sourceRegion.zoneDependentSkuCount !== 1 ? 's' : ''}
                                    {curated.sourceRegion?.zoneSupport?.mode === 'zone-redundant-unavailable' ? ' (effectively unavailable)' : ''}
                                  </Badge>
                                )}
                                {curated.sourceRegion?.effectiveSkuCount != null && curated.sourceRegion?.effectiveSkuCount !== (details?.summary?.sourceCount ?? curated.sourceRegion?.effectiveSkuCount) && (
                                  <Caption1 className={styles.zoneCardMeta}>Effective SKUs: {curated.sourceRegion.effectiveSkuCount} of {details?.summary?.sourceCount}</Caption1>
                                )}
                              </div>
                            )}
                          </div>
                          <div className={styles.zoneCard}>
                            <div className={styles.zoneCardLabel}>
                              <Caption1>{row.target_region}</Caption1>
                              <Caption1 className={styles.zoneCardMeta}>{curated.targetRegion?.zoneSupport?.notes || 'Regional zone posture.'}</Caption1>
                            </div>
                            <Badge appearance="filled" color={zoneSupportTone(curated.targetRegion?.zoneSupport?.mode)}>
                              {curated.targetRegion?.zoneSupport?.label || 'Unknown'}
                            </Badge>
                            {(curated.targetRegion?.zoneDependentSkuCount > 0 || (curated.targetRegion?.effectiveSkuCount != null && curated.targetRegion?.effectiveSkuCount !== (details?.summary?.targetCount ?? curated.targetRegion?.effectiveSkuCount))) && (
                              <div className={styles.zoneCardExtra}>
                                {curated.targetRegion?.zoneDependentSkuCount > 0 && (
                                  <Badge appearance="tint" color={curated.targetRegion?.zoneSupport?.mode === 'zone-redundant-unavailable' ? 'danger' : 'informative'}>
                                    {curated.targetRegion.zoneDependentSkuCount} zone-dependent SKU{curated.targetRegion.zoneDependentSkuCount !== 1 ? 's' : ''}
                                    {curated.targetRegion?.zoneSupport?.mode === 'zone-redundant-unavailable' ? ' (effectively unavailable)' : ''}
                                  </Badge>
                                )}
                                {curated.targetRegion?.effectiveSkuCount != null && curated.targetRegion?.effectiveSkuCount !== (details?.summary?.targetCount ?? curated.targetRegion?.effectiveSkuCount) && (
                                  <Caption1 className={styles.zoneCardMeta}>Effective SKUs: {curated.targetRegion.effectiveSkuCount} of {details?.summary?.targetCount}</Caption1>
                                )}
                              </div>
                            )}
                          </div>
                        </div>

                        {expandedSections.length ? (
                          <div className={styles.expandedBlock}>
                            <div className={styles.sectionHeader}>
                              <Subtitle1>Expanded raw capability details</Subtitle1>
                              <Badge appearance="outline">{expandedSections.reduce((total, section) => total + (section.count || 0), 0)}</Badge>
                            </div>
                            {expandedSections.map((section) => (
                              <details key={section.key || section.title} className={styles.expandedDetails}>
                                <summary className={styles.expandedSummary}>
                                  <div className={styles.expandedSummaryMeta}>
                                    <div>{section.title}</div>
                                    <Caption1>{section.description || 'Additional raw properties detected for this curated service.'}</Caption1>
                                  </div>
                                  <Badge appearance="outline">{section.count || 0}</Badge>
                                </summary>
                                <div className={styles.expandedBody}>
                                  {(section.groups || []).map((group) => (
                                    <details key={`${section.key || section.title}-${group.title}`} className={styles.expandedNestedDetails}>
                                      <summary className={styles.expandedNestedSummary}>
                                        <div>{group.title}</div>
                                        <Badge appearance="outline">{group.count || 0}</Badge>
                                      </summary>
                                      <div className={styles.expandedTable}>
                                        <div className={styles.expandedHeader}>
                                          <div className={styles.expandedHeaderCell}>Property</div>
                                          <div className={styles.expandedHeaderCell}>{row.source_region}</div>
                                          <div className={styles.expandedHeaderCell}>{row.target_region}</div>
                                          <div className={styles.expandedHeaderCell}>{row.source_region} details</div>
                                          <div className={styles.expandedHeaderCell}>{row.target_region} details</div>
                                        </div>
                                        {(group.items || []).map((item) => (
                                          <div key={item.key || item.label} className={styles.expandedRow}>
                                            <div className={`${styles.expandedCell} ${styles.expandedNameCell}`}>
                                              <div>{item.label}</div>
                                              <div className={styles.capabilityMeta}>{item.key}</div>
                                              {item.sourceMeta || item.targetMeta ? <div className={styles.monoText}>{[item.sourceMeta, item.targetMeta].filter(Boolean).join(' | ')}</div> : null}
                                            </div>
                                            <div className={styles.expandedCell}>
                                              <Badge appearance="filled" color={capabilityBadgeColor(item.sourceValue)}>{item.sourceValue || 'missing'}</Badge>
                                            </div>
                                            <div className={styles.expandedCell}>
                                              <Badge appearance="filled" color={capabilityBadgeColor(item.targetValue)}>{item.targetValue || 'missing'}</Badge>
                                            </div>
                                            <div className={`${styles.expandedCell} ${styles.expandedNoteCell}`}>{item.sourceDetails || 'No additional detail'}</div>
                                            <div className={`${styles.expandedCell} ${styles.expandedNoteCell}`}>{item.targetDetails || 'No additional detail'}</div>
                                          </div>
                                        ))}
                                      </div>
                                    </details>
                                  ))}
                                </div>
                              </details>
                            ))}
                          </div>
                        ) : null}

                      </>
                    ) : details?.layout === 'family-breakdown' && details?.families?.length ? (
                      <VmFamilyBreakdownTable details={details} comparison={details?.pricingComparison} row={row} styles={styles} />
                    ) : details?.layout === 'sku-breakdown' && details?.skus?.length ? (
                      <>
                        {details?.tierSummary?.length ? (
                          <div className={styles.tableWrap}>
                            <Table className={styles.detailDataTable}>
                              <TableHeader>
                                <TableRow>
                                  <TableHeaderCell>Disk tier</TableHeaderCell>
                                  <TableHeaderCell>{row.source_region}</TableHeaderCell>
                                  <TableHeaderCell>{row.target_region}</TableHeaderCell>
                                </TableRow>
                              </TableHeader>
                              <TableBody>
                                {details.tierSummary.map((tier) => (
                                  <TableRow key={`${row.provider}-${tier.tier}`}>
                                    <TableCell><TableCellLayout>{tier.tier}</TableCellLayout></TableCell>
                                    <TableCell><TableCellLayout>{tier.sourceCount}</TableCellLayout></TableCell>
                                    <TableCell><TableCellLayout>{tier.targetCount}</TableCellLayout></TableCell>
                                  </TableRow>
                                ))}
                              </TableBody>
                            </Table>
                          </div>
                        ) : null}

                        <DiskSkuBreakdownTable details={details} comparison={details?.pricingComparison} row={row} styles={styles} />
                      </>
                    ) : sections.length ? sections.map((section) => (
                      <div key={section.title} className={styles.detailSection}>
                        <div className={styles.sectionHeader}>
                          <Subtitle1>{section.title}</Subtitle1>
                          <Badge appearance="outline">{section.count}</Badge>
                        </div>
                        {section.items?.length ? (
                          <ul className={styles.detailList}>
                            {section.items.map((item) => (
                              <li key={`${section.title}-${item.resourceType}`} className={styles.detailItem}>
                                <div>{item.label}</div>
                                <div className={styles.monoText}>{item.resourceType}</div>
                              </li>
                            ))}
                          </ul>
                        ) : (
                          <Caption1>No listed capability types in this category.</Caption1>
                        )}
                        {section.omittedCount ? (
                          <Caption1>Plus {section.omittedCount} more capability type(s) not shown in this preview.</Caption1>
                        ) : null}
                      </div>
                    )) : (
                      <div className={styles.emptyBlock}>No enriched detail payload is available for this result.</div>
                    )}
                  </div>
                </details>
              );
            }) : (
              <div className={styles.emptyBlock}>
                {hasActiveFilters
                  ? 'No results match the current filters.'
                  : currentRun?.status === 'completed'
                    ? 'This run completed without any comparison rows.'
                    : currentRun?.status === 'failed'
                      ? 'This run failed before results were generated.'
                      : 'No comparison results are available for the selected run yet.'}
              </div>
            )}
          </div>
        ) : (
          <div className={styles.tableWrap}>
          <Table aria-labelledby={resultsTableId} className={styles.table}>
            <TableHeader>
              <TableRow>
                <TableHeaderCell>Service</TableHeaderCell>
                <TableHeaderCell>Provider</TableHeaderCell>
                <TableHeaderCell>Family</TableHeaderCell>
                <TableHeaderCell>Status</TableHeaderCell>
                <TableHeaderCell>Source</TableHeaderCell>
                <TableHeaderCell>Target</TableHeaderCell>
                <TableHeaderCell>Notes</TableHeaderCell>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pagedResults.length ? pagedResults.map((row) => {
                const details = tryParseDetails(row.details_json);
                const pricingText = pricingDisplayText(details?.pricingSummary, details?.pricingComparison);
                return (
                <TableRow key={row.row_key || `${row.provider}-${row.service}-${row.source_region}-${row.target_region}`}>
                  <TableCell><TableCellLayout><div className={styles.wrapText}>{row.service}</div></TableCellLayout></TableCell>
                  <TableCell><TableCellLayout><div className={styles.providerText}>{row.provider}</div></TableCellLayout></TableCell>
                  <TableCell><TableCellLayout><div className={styles.familyText}>{formatFamilyLabel(resultCanonicalFamily(row))}</div></TableCellLayout></TableCell>
                  <TableCell><TableCellLayout>{renderStatusBadge(row.availability, 'tint', row.source_region, row.target_region)}</TableCellLayout></TableCell>
                  <TableCell><TableCellLayout>{row.source_region}</TableCellLayout></TableCell>
                  <TableCell><TableCellLayout>{row.target_region}</TableCellLayout></TableCell>
                  <TableCell>
                    <TableCellLayout>
                      <div className={styles.wrapText}>{row.notes || 'No additional notes'}</div>
                      <Caption1>{pricingText}</Caption1>
                    </TableCellLayout>
                  </TableCell>
                </TableRow>
                );
              }) : (
                <TableRow>
                  <TableCell colSpan={7}>
                    <div className={styles.emptyBlock}>
                      {hasActiveFilters
                        ? 'No results match the current filters.'
                        : currentRun?.status === 'completed'
                          ? 'This run completed without any comparison rows.'
                          : currentRun?.status === 'failed'
                            ? 'This run failed before results were generated.'
                            : 'No comparison results are available for the selected run yet.'}
                    </div>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
          </div>
        )}

        <div className={styles.pager}>
          <Caption1>
            Showing {(filteredResults.length && ((safePageNumber - 1) * pageSize + 1)) || 0} to {Math.min(safePageNumber * pageSize, filteredResults.length)} of {filteredResults.length} services
          </Caption1>
          <div className={styles.pagerActions}>
            <Button icon={<ChevronLeft20Regular />} disabled={safePageNumber <= 1} onClick={() => setPageNumber((current) => Math.max(1, current - 1))}>
              Previous
            </Button>
            <Badge appearance="filled">Page {safePageNumber} of {totalPages}</Badge>
            <Button icon={<ChevronRight20Regular />} iconPosition="after" disabled={safePageNumber >= totalPages} onClick={() => setPageNumber((current) => Math.min(totalPages, current + 1))}>
              Next
            </Button>
          </div>
        </div>
      </Card>
    );
  }

  return (
    <FluentProvider theme={activeTheme} style={{ minHeight: '100vh' }}>
    <div className={styles.shell} style={themeVars}>
      <div className={styles.frame}>
        <header className={styles.hero}>
          <div className={styles.heroCopy}>
            <Caption1 className={styles.eyebrow}>Azure regional comparisons</Caption1>
            <h1 className={styles.heroTitle}>Compare Azure services across regions.</h1>
            <Body1 className={styles.heroText}>
              Start with your current estate or compare broader regional coverage without leaving the same workspace.
            </Body1>
            <div className={styles.heroActions}>
              <Button
                appearance="secondary"
                icon={themeMode === 'dark' ? <WeatherSunny20Regular /> : <WeatherMoon20Regular />}
                onClick={() => setThemeMode((current) => (current === 'dark' ? 'light' : 'dark'))}
              >
                {themeMode === 'dark' ? 'Light mode' : 'Dark mode'}
              </Button>
              <div className={styles.heroStatusStrip}>
                <Caption1 className={styles.heroStatusText}>Signed in as {signedInLabel}</Caption1>
                <div className={styles.heroStatusBadges}>
                  {isInitializing ? <Spinner size="tiny" label="Refreshing" /> : null}
                  {renderHealthSummary()}
                </div>
              </div>
            </div>
          </div>
        </header>

        <div className={styles.shellLayout}>
          <aside>
            <Card className={styles.navCard}>
              <div className={styles.sectionMeta}>
                <Caption1>Workspace</Caption1>
                <Subtitle1>Move between views</Subtitle1>
              </div>
              <TabList
                appearance="subtle"
                className={styles.navTabList}
                selectedValue={activeView}
                vertical
                onTabSelect={(_, data) => setActiveView(data.value)}
              >
                <Tab icon={<PlayCircle24Regular />} value="overview">Overview</Tab>
                <Tab icon={<DataHistogram24Regular />} value="results">Results</Tab>
                <Tab icon={<History24Regular />} value="runs">Runs</Tab>
              </TabList>
            </Card>
          </aside>

          <section className={styles.contentColumn}>
            <div className={styles.summaryGrid}>
              {activeView === 'overview' ? (
                <>
                  <Card className={styles.summaryCard} style={{ backgroundColor: 'var(--app-summary-a)' }}>
                    <Caption1>Comparison mode</Caption1>
                    <div className={styles.summaryValueCompact}>{selectedMode?.label || `${formatModeLabel(formValues.comparisonMode)} comparison`}</div>
                  </Card>
                  <Card className={styles.summaryCard} style={{ backgroundColor: 'var(--app-summary-b)' }}>
                    <Caption1>Source region</Caption1>
                    <div className={styles.summaryValueCompact}>{formValues.sourceRegion}</div>
                  </Card>
                  <Card className={styles.summaryCard} style={{ backgroundColor: 'var(--app-summary-c)' }}>
                    <Caption1>Target region</Caption1>
                    <div className={styles.summaryValueCompact}>{formValues.targetRegion}</div>
                  </Card>
                  <Card className={styles.summaryCard} style={{ backgroundColor: 'var(--app-summary-d)' }}>
                    <Caption1>Latest run</Caption1>
                    <div className={styles.summaryValueCompact}>{latestRunLabel}</div>
                  </Card>
                </>
              ) : (
                <>
                  <Card className={styles.summaryCard} style={{ backgroundColor: 'var(--app-summary-a)' }}>
                    <Caption1>Visible services</Caption1>
                    <div className={styles.summaryValue}>{summary.total}</div>
                  </Card>
                  <Card className={styles.summaryCard} style={{ backgroundColor: 'var(--app-summary-b)' }}>
                    <Caption1>Matches in view</Caption1>
                    <div className={styles.summaryValue}>{summary.matching}</div>
                  </Card>
                  <Card className={styles.summaryCard} style={{ backgroundColor: 'var(--app-summary-c)' }}>
                    <Caption1>Identity fallbacks</Caption1>
                    <div className={styles.summaryValue}>{summary.identityGaps}</div>
                  </Card>
                  <Card className={styles.summaryCard} style={{ backgroundColor: 'var(--app-summary-d)' }}>
                    <Caption1>Service families</Caption1>
                    <div className={styles.summaryValue}>{summary.families}</div>
                  </Card>
                </>
              )}
            </div>

            {activeView === 'overview' ? renderOverview() : null}
            {activeView === 'results' ? renderResultsView() : null}
            {activeView === 'runs' ? renderRunsView() : null}
          </section>
        </div>
      </div>
    </div>
    </FluentProvider>
  );
}