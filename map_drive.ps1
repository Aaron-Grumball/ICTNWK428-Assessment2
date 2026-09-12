# Maps the Mick And Macks shared directory as drive S
New-PSDrive `
    -Name "S" `
    -PSProvider FileSystem `
    -Root "\\Server1\mickandmacks_share" `
    -Persist