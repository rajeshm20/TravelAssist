# Set `main` as the default branch (GitHub)

## 1) Rename your local branch to `main` (if needed)

```bash
git branch -M main
git push -u origin main
```

## 2) Change the default branch on GitHub

1. Open **GitHub → Repo → Settings → Branches**
2. Under **Default branch**, select `main`
3. Save

## 3) (Optional) Remove the old branch from origin

```bash
git push origin --delete master
```

