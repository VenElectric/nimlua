import fs from "node:fs";
import { exec } from "node:child_process";

const files = fs.readdirSync("./src")

const errors = []

for (const file of files) {
  if (file.endsWith(".nim")) {
    let command = `nim check src/${file}`
    exec(command, (err, stdout, stderr) => {
      console.log("==== ",file," =====")
      if (err) {
          errors.push({file,err})
      }
      if (stdout.length > 0) {
        console.log(stdout)
      }
      if (stderr.length > 0) {
        console.log(stderr)
      }
    console.log("==== END ====")
    }) 
  }
}

if (errors.length > 0) {
  for (const err of errors) {
    console.log(err.file)
    console.log(err.err)
  }
}

