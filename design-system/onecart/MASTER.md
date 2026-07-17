# Design System Master File

> **LOGIC:** When building a specific page, first check `design-system/pages/[page-name].md`.
> If that file exists, its rules **override** this Master file.
> If not, strictly follow the rules below.

---

**Project:** OneCart
**Generated:** 2026-07-16 17:07:11
**Category:** Grocery & Shopping List
**Design Dials:** Variance 3/10 (Centered / Minimal) | Motion 3/10 (Subtle) | Density 5/10 (Standard)

---

## Global Rules

### Color Palette

| Role | Hex | CSS Variable |
|------|-----|--------------|
| Primary | `#34785B` | `--color-primary` |
| On Primary | `#FFFFFF` | `--color-on-primary` |
| Secondary | `#E1EFE7` | `--color-secondary` |
| Accent/CTA | `#34785B` | `--color-accent` |
| Background | `#F5F6F3` | `--color-background` |
| Foreground | `#17211C` | `--color-foreground` |
| Muted | `#EEF0EC` | `--color-muted` |
| Border | `#DDE2DC` | `--color-border` |
| Destructive | `#B94A48` | `--color-destructive` |
| Ring | `#34785B` | `--color-ring` |

**Color Notes:** Neutral white/grey surfaces with one calm green action color. Amber is reserved for warnings only.

### Typography

- **Heading Font:** system UI
- **Body Font:** system UI
- **Mood:** familiar, calm, legible, platform-native
- **Font Stack:** `-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`

**CSS Import:**
```css
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
```

### Spacing Variables

*Density: 5/10 — Standard*

| Token | Value | Usage |
|-------|-------|-------|
| `--space-xs` | `4px` / `0.25rem` | Tight gaps |
| `--space-sm` | `8px` / `0.5rem` | Icon gaps, inline spacing |
| `--space-md` | `16px` / `1rem` | Standard padding |
| `--space-lg` | `24px` / `1.5rem` | Section padding |
| `--space-xl` | `32px` / `2rem` | Large gaps |
| `--space-2xl` | `48px` / `3rem` | Section margins |
| `--space-3xl` | `64px` / `4rem` | Hero padding |

### Shadow Depths

| Level | Value | Usage |
|-------|-------|-------|
| `--shadow-sm` | `0 1px 2px rgba(0,0,0,0.05)` | Subtle lift |
| `--shadow-md` | `0 4px 6px rgba(0,0,0,0.1)` | Cards, buttons |
| `--shadow-lg` | `0 10px 15px rgba(0,0,0,0.1)` | Modals, dropdowns |
| `--shadow-xl` | `0 20px 25px rgba(0,0,0,0.15)` | Hero images, featured cards |

---

## Component Specs

### Buttons

```css
/* Primary Button */
.btn-primary {
  background: #34785B;
  color: white;
  padding: 12px 24px;
  border-radius: 14px;
  font-weight: 600;
  transition: all 200ms ease;
  cursor: pointer;
}

.btn-primary:hover {
  opacity: 0.9;
  background: #2C664D;
}

/* Secondary Button */
.btn-secondary {
  background: transparent;
  color: #2C664D;
  border: 1px solid #B9CFC3;
  padding: 12px 24px;
  border-radius: 14px;
  font-weight: 600;
  transition: all 200ms ease;
  cursor: pointer;
}
```

### Cards

```css
.card {
  background: #FFFFFF;
  border: 1px solid #E5E8E4;
  border-radius: 18px;
  padding: 16px;
  box-shadow: var(--shadow-sm);
  transition: all 200ms ease;
  cursor: pointer;
}

.card:hover {
  border-color: #CAD8D0;
}
```

### Inputs

```css
.input {
  padding: 12px 16px;
  border: 1px solid #E2E8F0;
  border-radius: 14px;
  font-size: 16px;
  transition: border-color 200ms ease;
}

.input:focus {
  border-color: #34785B;
  outline: none;
  box-shadow: 0 0 0 3px #34785B24;
}
```

### Modals

```css
.modal-overlay {
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(4px);
}

.modal {
  background: white;
  border-radius: 16px;
  padding: 32px;
  box-shadow: var(--shadow-xl);
  max-width: 500px;
  width: 90%;
}
```

---

## Style Guidelines

**Style:** Calm utility minimalism

**Keywords:** calm, familiar, light, content-first, touch-friendly, restrained

**Best For:** everyday family productivity and grocery planning

**Key Effects:** clear type hierarchy, 16-20px cards, thin borders, subtle single-level shadows, 4/8pt spacing

### Page Pattern

**Pattern Name:** Mobile task flow

- **Interaction Strategy:** One clear primary action per screen, five-item bottom navigation, progressive sheets for secondary actions.
- **CTA Placement:** Bottom-safe and reachable by thumb; never oversized.
- **Section Order:** screen header, primary summary, active task content, optional supporting content.

---

## Motion

**Stagger List** (Subtle) — Trigger: load or scroll | Duration: 250-350ms | Easing: `power1.out`

```js
gsap.from('.list-item', { opacity: 0, y: 8, duration: 0.3, stagger: 0.03 });
```

**Framework notes:** Select items with a stable class/data-attribute (not array index) so re-renders in React don't break targeting

- ✅ Keep per-item stagger delay small (0.02-0.04s) for lists longer than 10 items
- ❌ Don't stagger by more than 0.1s per item on long lists; total reveal time becomes sluggish
- ⚡ For virtualized lists, only animate items currently mounted in the DOM

---

## Anti-Patterns (Do NOT Use)

- ❌ Complex shadows
- ❌ 3D effects
- ❌ Muted colors
- ❌ Low energy

### Additional Forbidden Patterns

- ❌ **Emojis as icons** — Use SVG icons (Heroicons, Lucide, Simple Icons)
- ❌ **Missing cursor:pointer** — All clickable elements must have cursor:pointer
- ❌ **Layout-shifting hovers** — Avoid scale transforms that shift layout
- ❌ **Low contrast text** — Maintain 4.5:1 minimum contrast ratio
- ❌ **Instant state changes** — Always use transitions (150-300ms)
- ❌ **Invisible focus states** — Focus states must be visible for a11y

---

## Pre-Delivery Checklist

Before delivering any UI code, verify:

- [ ] No emojis used as icons (use SVG instead)
- [ ] All icons from consistent icon set (Heroicons/Lucide)
- [ ] `cursor-pointer` on all clickable elements
- [ ] Hover states with smooth transitions (150-300ms)
- [ ] Light mode: text contrast 4.5:1 minimum
- [ ] Focus states visible for keyboard navigation
- [ ] `prefers-reduced-motion` respected
- [ ] Responsive: 375px, 768px, 1024px, 1440px
- [ ] No content hidden behind fixed navbars
- [ ] No horizontal scroll on mobile
