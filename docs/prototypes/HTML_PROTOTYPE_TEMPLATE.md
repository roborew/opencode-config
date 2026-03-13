# HTML Prototype Generation Template

Use this template for `.plan/design.<slug>.md` artifacts and `ux-dev` execution prompts.

Act as an expert frontend developer and UX/UI designer. Your task is to generate a complete, responsive, and accessible website prototype based on the requirements below.

**Tech Stack:**
- Framework: Vanilla HTML5
- Styling: Tailwind CSS (via Play CDN)
- Icons: Phosphor Icons or FontAwesome (via CDN)
- Interactivity: Vanilla JavaScript (or Alpine.js via CDN if complex state is needed)

**Project Description:**
[Insert a brief description of the site]

**Design & UI Guidelines:**
1. **Layout Strategy:** Use a mobile-first approach. Rely exclusively on modern CSS Grid and Flexbox for structural layouts.
2. **Tailwind Best Practices:** Strictly use Tailwind's utility classes. Do not use inline CSS or `<style>` blocks unless absolutely necessary for custom keyframe animations.
3. **Aesthetics:** Create a clean interface with ample whitespace, clear visual hierarchy, and polished typography. Apply a clear color palette.
4. **Realistic Content:** Use context-aware placeholder copywriting. Do not use generic lorem ipsum.

**Development Standards:**
1. **Semantic HTML:** Structure the DOM using proper HTML5 tags (`<header>`, `<nav>`, `<main>`, `<section>`, `<footer>`).
2. **Accessibility (a11y):** Ensure standard color contrast, support keyboard navigability, and include `aria-labels` for interactive elements.
3. **Responsiveness:** Ensure the UI scales across mobile (`sm`), tablet (`md`), and desktop (`lg`/`xl`) breakpoints.

**Output Instructions:**
- Output the prototype as complete HTML files under `.prototype/<slug>/` (single page or multiple pages depending on scope).
- Include Tailwind Play CDN in `<head>`:
  - `<script src="https://cdn.tailwindcss.com"></script>`
- Configure custom Tailwind colors/fonts in `<head>` via:
  - `tailwind.config = {...}`
- Include interactive JavaScript in a `<script>` tag before `</body>`.
- Keep prototype output framework-agnostic. Framework integration is a later step.
