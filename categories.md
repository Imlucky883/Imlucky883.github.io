---
layout: page
title: Post Categories
---
<ul class="category-list">
  {% assign categories = site.categories | sort %}
  {% for category in categories %}
    <li style="margin-bottom: 5px;">
      <a href="/categories/{{ category[0] | slugify }}/">{{ category[0] | capitalize }}</a>
    </li>
  {% endfor %}
</ul>

<script>
function filter(id) {
  document.querySelectorAll('.category-section').forEach(el => el.style.display = 'none');
  document.getElementById('category-list').style.display = 'none';
  document.getElementById(id).style.display = 'block';
}
function showAll() {
  document.querySelectorAll('.category-section').forEach(el => el.style.display = 'none');
  document.getElementById('category-list').style.display = 'block';
}
</script>