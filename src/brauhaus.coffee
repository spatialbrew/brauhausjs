###
@preserve
Brauhaus.js Beer Calculator
Copyright 2013 Daniel G. Taylor <danielgtaylor@gmail.com>
https://github.com/danielgtaylor/brauhausjs
###

# Create the base module so it works in both node.js and in browsers
Brauhaus = exports? and exports or @Brauhaus = {}

# Regular expressions to match for steeping grains, such as caramel malts.
# This is used to create the recipe timeline.
STEEP_FERMENTABLES = /biscuit|black|cara|chocolate|crystal|munich|roast|special ?b|toast|victory|vienna/i

# Regular expressions to match for boiling sugars (DME, LME, etc).
# This is used to create the recipe timeline.
BOIL_FERMENTABLES = /candi|candy|dme|dry|extract|honey|lme|liquid|sugar|syrup|turbinado/i

# Friendly beer color names and their respective SRM values
COLOR_NAMES = [
    [2, 'pale straw'],
    [3, 'straw'],
    [4, 'pale gold'],
    [6, 'deep gold'],
    [9, 'pale amber'],
    [12, 'medium amber'],
    [15, 'deep amber'],
    [18, 'amber brown'],
    [20, 'brown'],
    [24, 'ruby brown'],
    [30, 'deep brown'],
    [40, 'black']
]

# Convert SRM color values to [r, g, b] triplets
Brauhaus.srmToRgb = (srm) ->
    r = Math.round(Math.min(255, Math.max(0, 255 * Math.pow(0.975, srm))))
    g = Math.round(Math.min(255, Math.max(0, 245 * Math.pow(0.88, srm))))
    b = Math.round(Math.min(255, Math.max(0, 220 * Math.pow(0.7, srm))))
    
    [r, g, b]

# Convert SRM color values to CSS-friendly strings
Brauhaus.srmToCss = (srm) ->
    [r, g, b] = Brauhaus.srmToRgb srm
    "rgb(#{ r }, #{ g }, #{ b })"

# Convert SRM color values into friendly names
Brauhaus.srmToName = (srm) ->
    color = COLOR_NAMES[0][1]

    for item in COLOR_NAMES
        color = item[1] if item[0] <= srm

    color

# A base class which sets passed options as properties on itself.
class Brauhaus.OptionConstructor
    constructor: (options) ->
        # Set any properties passed in
        for own property of options
            @[property] = options[property]

###
Base class for new recipe ingredients. Each ingredient gets a name,
which defaults to 'New ' + the class name. For classes that inherit
Ingredient it will use their name, e.g:
###
class Brauhaus.Ingredient extends Brauhaus.OptionConstructor
    constructor: (options) ->
        # Set default name based on the class name
        @name = 'New ' + @constructor.name

        super(options)

###
A fermentable ingredient, e.g. liquid malt extract. Each ingredient
has a name, weight in kilograms, yield as a percentage, color in
degrees SRM, and is marked as either late or normal. Late additions
affect hop utilization. Each fermentable also provides methods for
getting the type, addition, color name, and gravity units per volume
of liquid.
###
class Brauhaus.Fermentable extends Brauhaus.Ingredient
    weight: 1.0
    yield: 75.0
    color: 2.0
    late: false

    # Get the type of fermentable based on its name, either extract
    # or grain (steeping / mashing)
    type: ->
        if BOIL_FERMENTABLES.exec(@name) then 'extract' else 'grain'

    # When is this item added in the brewing process? Boil, steep, or mash?
    addition: ->
        value = 'mash'

        # Forced values take precedence, then search with regex
        if /mash/i.exec @name
            value = 'mash'
        else if /steep/i.exec @name
            value = 'steep'
        else if /boil/i.exec @name
            value = 'boil'
        else if BOIL_FERMENTABLES.exec @name
            value = 'boil'
        else if STEEP_FERMENTABLES.exec @name
            value = 'steep'

        value

    # Get the gravity units for a specific liquid volume with 100% efficiency
    gu: (gallons = 1.0) ->
        # gu = parts per gallon * weight in pounds / gallons
        (@yield * 0.46214) * (@weight * 2.20462) / gallons

    # Get a rgb triplet for this fermentable's color
    colorRgb: ->
        Brauhaus.srmToRgb @color

    # Get a CSS-friendly string for this fermentable's color
    colorCss: ->
        Brauhaus.srmToCss @color

    # Get a friendly human-readable color name
    colorName: ->
        Brauhaus.srmToName @color

###
A spice ingredient, e.g. cascade hops or crushed coriander. Each spice
has a weight in kilograms, alpha acid (aa) percentage, use (mash, boil,
primary, secondary, etc), time in minutes to add the spice, and the
spice's form (whole, leaf, pellet, crushed, ground, etc).
###
class Brauhaus.Spice extends Brauhaus.Ingredient
    weight: 0.025
    aa: 0.0
    use: 'boil'
    time: 60
    form: 'pellet'

###
A yeast ingredient, e.g. Safbrew T-58 or Brett B. Each yeast has a
type (ale, lager, other), a form (liquid, dry), and an attenuation
percentage that describes the maximum attenuation under ideal
conditions.
###
class Brauhaus.Yeast extends Brauhaus.Ingredient
    type: 'ale'
    form: 'liquid'
    attenuation: 75.0

###
A beer recipe, consisting of various ingredients and metadata which
provides a calculate() method to calculate OG, FG, IBU, ABV, and a
timeline of instructions for brewing the recipe.
###
class Brauhaus.Recipe extends Brauhaus.OptionConstructor
    name: 'New Recipe'
    description: 'Recipe description'
    author: 'Anonymous Brewer'
    boilSize: 10.0
    batchSize: 20.0

    steepEfficiency: 0.5
    mashEfficiency: 0.75

    fermentables: null
    spices: null
    yeast: null

    og: 0.0
    fg: 0.0
    color: 0.0
    ibu: 0.0
    abv: 0.0

    constructor: (options) ->
        @fermentables = []
        @spices = []
        @yeast = []

        super(options)

    add: (type, values) ->
        if type is 'fermentable'
            @fermentables.push new Brauhaus.Fermentable(values)

    calculate: ->
        @og = 1.0
        
        for fermentable in @fermentables
            efficiency = 1.0
            addition = fermentable.addition()
            if addition is 'steep'
                efficiency = @steepEfficiency
            else if addition is 'mash'
                efficiency = @mashEfficiency

            @og += fermentable.gu(@batchSize * 264.172) * efficiency

    toXml: ->
        xml = '<?xml version="1.0" encoding="utf-8"?><recipes><recipe>'

        xml += '<fermentables><version>1</version>'
        for fermentable in @fermentables
            xml += "<name>#{ fermentable.name }</name>"
            xml += "<type>#{ fermentable.type() }</name>"
            xml += "<weight>#{ fermentable.weight.toFixed 1 }</weight>"
            xml += "<yield>#{ fermentable.yield.toFixed 1 }</yield>"
            xml += "<color>#{ fermentable.color.toFixed 1 }</color>"
        xml += '</fermentables>'

        xml += '</recipe></recipes>'