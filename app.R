library(shiny)
source("1-GUI-YeliCLE-findings.R")
model.res.fig <-"No"

# Define UI for data upload app ----
ui <- fluidPage(

  # App title ----
  titlePanel("Rossel Island child language environment estimates"),

  # Sidebar layout with input and output definitions ----
  sidebarLayout(

    # Sidebar panel for inputs ----
    sidebarPanel(

      # Input: Sample ----
      selectizeInput("sample", "Which clips?",
                   choices = c("Random", "High turn-taking"),
                   options = list(
                     placeholder = 'Select a clip type below',
                     onInitialize = I('function() { this.setValue(""); }'))),

      # Input: Data version ----
      selectizeInput("version", "Which version of the dataset?",
                   choices = c("Casillas, Brown, & Levinson (accepted August 2020)"),
                   options = list(
                     placeholder = 'Select a dataset version below',
                     onInitialize = I('function() { this.setValue(""); }'))),

      # Input: Measures ----
      selectizeInput("measures", "Which measure?",
                   choices = c("Target-child-directed speech (TCDS) min/hr",
                               "All other-directed-speech (ODS) min/hr",
                               "All speech (XDS) min/hr"),
                   options = list(
                     placeholder = 'Select an measure below',
                     onInitialize = I('function() { this.setValue(""); }'))),

      # # Input: Models ----
      # selectizeInput("model", "Show model output(s)?",
      #              choices = c("Yes", "No"),
      #              options = list(
      #                placeholder = 'Select an option below',
      #                onInitialize = I('function() { this.setValue(""); }'))),

      # Submit button:
      actionButton("submit", "Update")
    ),
    
    # Main panel for displaying outputs ----
    mainPanel(
      uiOutput("report")
    )
  )
)

# Define server logic to read selected file ----
server <- function(input, output) {
  report <- eventReactive(input$submit, {
    req(input$sample, input$version, input$measures)
    retrieve.summary(input$sample,
                  input$version,
                  input$measures)
  })

  output$report <- renderUI({
    req(report())
    
    tagList(
      tags$h1("Summary statistics"),
      renderTable(report()$sum.stat.tbl),
      tags$h1("Graphical summary"),
      renderPlot(report()$sum.stat.fig),
      tags$h1("Model summary (if it exists)"),
      renderTable(report()$model.output.tbl),
      img(src=report()$model.res.fig, align = "left"),
      tags$br()
    )
  })

  }

# Create Shiny app ----
shinyApp(ui, server)