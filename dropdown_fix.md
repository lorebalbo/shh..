Here is how you can fix both the "Provider Type" and "Model Name" dropdowns to make them look professional and fit perfectly with your current aesthetic:

### 1. Give Them a Container (Crucial)
Right now, your text inputs ("API Key" and "Endpoint URL") look great because they have that soft, rounded, slightly darker background. **Your dropdowns need exactly the same treatment.**
* Wrap the selected value (e.g., "Anthropic" or "claude-sonnet-...") in a container that has the exact same background color, border-radius, and height as your text inputs.
* This instantly signals to the user: *"This is a form field you can interact with."*

### 2. Fix the Layout and Alignment
Consistency is key in form design.
* **Stack them:** Notice how "API Key" is placed right above its input field? Do the same for the dropdowns. Put the "Provider Type" label directly above the dropdown container, rather than beside it.
* **Full Width:** Make the dropdown container span the same width as the text inputs so everything aligns nicely on the right edge.

### 3. Add a Clear Indicator
The tiny, low-contrast double-arrow icon next to the text is too subtle.
* Place a clear, recognizable **chevron-down icon** (like a `v`) on the far right side of the new container.
* Keep the text aligned to the left, matching the padding of your text inputs.

### 4. Redesign the Popup Menu
The dark grey popup menu clashes heavily with the elegant, light cream theme you have going on.
* **Color:** Change the dropdown menu's background to a light color (either pure white or the same off-white of your modal). Use dark text for the options.
* **Depth:** Add a soft, transparent drop shadow (like a 10% opacity black shadow) to the menu so it visually "floats" above the modal content.
* **Hover state:** Add a subtle background color change (like a very light grey) when hovering over the options ("Anthropic", "OpenAI", etc.).
