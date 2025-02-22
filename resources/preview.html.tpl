{{define "preview"}}
<section class="blog-preview">
    <h2 class="blog-preview-title">{{.Title}}</h2>
    <p class="blog-preview-meta">Posted on {{.Created}} by {{.Author}} (updated at {{.Updated}})</p>
    <p class="blog-preview-content">
        No Preview available currently...
    </p>
    <a href="{{.ID}}" class="read-more">Read More</a>
</section>
{{end}}
