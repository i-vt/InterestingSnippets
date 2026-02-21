from github import Github

# 🔐 Your GitHub token
token = "YOUR_GITHUB_TOKEN"

# Connect to GitHub
g = Github(token)

# Get repo
repo = g.get_repo("gagabuga/a324234")

# Read local file
with open("example.txt", "r") as f:
    content = f.read()

# Upload file
repo.create_file(
    path="example.txt",          # path in repo
    message="Add example.txt",   # commit message
    content=content,
    branch="main"                # or your branch
)

print("Uploaded!")
