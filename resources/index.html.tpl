<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{.BlogTitle}}</title>
    <link rel="stylesheet" href="resources/styles.css">
</head>
<body>
    {{template "header" .}}
    <br/>

    <main class="main container">
    {{range .postsMetadata}}
        {{template "preview" .}}
    {{end}}
    </main>

    {{template "footer" .}}
</body>
</html>
