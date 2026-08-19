import fs from "node:fs";
import { exec } from "node:child_process";

const files = fs.readdirSync("./src")

const errors = []

for (const file of files) {
  if (file.endsWith(".nim")) {
    let command = `nimpretty src/${file}`
    exec(command, (err, stdout, stderr) => {
      if (err) {
          errors.push({file,err})
      }
    }) 
  }
}

if (errors.length > 0) {
  for (const err of errors) {
    console.log(err.file)
    console.log(err.err)
  }
}

