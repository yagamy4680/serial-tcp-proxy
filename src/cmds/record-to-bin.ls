require! <[fs]>
{Buffer} = require \buffer

ERR_EXIT = (err) ->
  console.error err
  console.dir err
  return process.exit 1
  

module.exports = exports =
  command: "record-to-bin <record_file>"
  describe: "convert the recorded TSV/CSV file to a single binary blob file"

  builder: (yargs) ->
    yargs
      .alias \o, \output
      .default \o, null
      .describe \o, "the path to the output file"
      .demand <[o]>


  handler: (argv) ->
    {output, record_file} = argv
    console.log "output = #{output}"
    console.log "record_file = #{record_file}"
    (read_err, data) <- fs.readFile record_file
    return ERR_EXIT read_err if read_err?
    console.log "read #{data.length} bytes from #{record_file}"
    text = data.toString!
    xs = text.split '\n'
    xs = [ x for x in xs when x.startsWith "!" ]
    xs = [ (x.split ' ') for x in xs ]
    console.log "parse to #{xs.length} lines"
    xs = [ x[3] for x in xs ]
    xs = xs.join ''
    xs = Buffer.from xs, 'hex'
    console.log "convert to #{xs.length} bytes in binary"
    (write_err) <- fs.writeFile output, xs
    return ERR_EXIT write_err if write_err?
    return console.log "write #{xs.length} bytes to #{output} ,,,"