# directivity-utils

This is a very early pre pre pre alpha of a script to create a directivity sonogram based on measurements dumped out of [REW] (http://www.roomeqwizard.com/) (and until such time as http://www.hometheatershack.com/forums/rew-forum/111090-feature-request-polar-response-plots.html is implemented).

# What is a polar map?

See [this article] (http://www.acousticfrontiers.com/20131129controlled-directivity-speakers-open-up-your-acoustic-treatment-options/) for a summary. The approach, I believe, originates from Geddes and has been subsequently implemented in [ARTA] (http://www.artalabs.hr/). This implementation uses the same colour scheme (the matlab jet colourmap) for consistency.

# What do I need to get started?

* a set of measurements containing appropriately measured data of a loudspeaker taken at various angles
* either
    * a linux box
    * a windows box with cygwin - install from [here](https://www.cygwin.com/)
* gnuplot
* awk

# How do I generate a sonogram?

NB: these instructions assume you are using REW, other software probably works as they all seem to stick to the same space delimited [FRD] (http://www.cross-spectrum.com/weblog/2010/03/05) format.

## Prepare the Input Data

* take measurements in your usual fashion at various degrees off axis
* create a directory to store the exported data
* export each measurement to a text file in space delimited FRD format named `<degrees>.dat` (select measurement, file/export/measurement as text, enter file name)

NB: see the [sample] dir in this repo for an example of the exported data

### WARNING!

the script has hardcoded axis ranges atm so it assumes the measurement peaks at ~74dB, you either need to offset your data before export OR (better) edit the values in the script before you generate the plot

## Generate the Plot

NB: assumes generate.sh from this repo is on your path and is executable

* open a shell in the directory containing the data

    generate.sh

* look for a file named output.png in the dir

# TODO

NB: this is quite the hack atm so there is loads that could be done so only the obvious stuff is listed

## Processing

* determine min/max values per axis from the data supplied
* provide a "normalise to 0 degrees" function

## Formatting

* label the contours as -3, -6, -9 etc
* fix the colour scheme applied to the contour lines

## User Experience

* don't eagerly delete existing files
* accept cmdline options where appropriate
 