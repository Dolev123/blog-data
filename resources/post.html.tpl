<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{.BlogTitle}}</title>
    <link rel="stylesheet" href="resources/styles.css">
    <link rel="stylesheet" href="resources/post.css">
</head>
<body>
    {{template "header" .}}
    <main class="main container">
        <article class="post">
         <p class="post-meta">Posted on {{.metadata.Created}} by {{.metadata.Author}} (updated at {{.metadata.Updated}})</p>
        {{.Content}}
        </article>
        <br/>
        <a href="/" class="read-more">Back to Home</a>
    </main>
    {{template "footer" .}}
</body>
</html>
