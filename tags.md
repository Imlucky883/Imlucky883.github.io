---
layout: page
title: Content Tags
---

<ul style="column-count: 2; list-style-type: disc; margin-left: 20px;">
  {% assign tags = site.tags | sort %}
  {% for tag in tags %}
    <li style="margin-bottom: 5px;">
      <a href="/tags/{{ tag[0] | slugify }}/">{{ tag[0] }}</a>
    </li>
  {% endfor %}
</ul>