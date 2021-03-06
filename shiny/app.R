# install.packages('DT')
# install.packages('ibmdbR')
# install.packages('plotly')

library(shiny)
library(plotly)
library(plyr)
library(DT)

# Enter your dashDB credentials below
dsn.hostname <- # HOSTNAME HERE
dsn.uid <- # USER ID HERE
dsn.pwd <- # PASSWORD HERE
dsn.database <- 'BLUDB'
dsn.port <- "50000"  
dsn.protocol <- "TCPIP"  

conn.path <- paste0(
  dsn.database,  
  ";DATABASE=",dsn.database,
  ";HOSTNAME=",dsn.hostname,
  ";PORT=",dsn.port,
  ";PROTOCOL=",dsn.protocol,
  ";UID=",dsn.uid,
  ";PWD=",dsn.pwd
)
table.string = 'DASH6815.FEMALE_TRAFFICKING'  

# Named colors for the pie graph
white <- rgb(255, 255, 255, maxColorValue=255)
darkred <- rgb(139, 0, 0, maxColorValue=255)
darkgreen <- rgb(0, 100, 0, maxColorValue=255)
coral <- rgb(255, 127, 80, maxColorValue=255)
gray <- rgb(128, 128, 128, maxColorValue=255)
brown2 <- rgb(238, 59, 59, maxColorValue=255)
darkgoldenrod4 <- rgb(139, 101, 9, maxColorValue=255)
darkolivegreen4 <- rgb(110, 139, 61, maxColorValue=255)

# Vetting categories as strings
category.as.string <- function(catnum) {
  i <- as.integer(catnum)
  if(!is.na(i)) {
    if (i == 10) return('HIGH')
    if (i == 20) return('MEDIUM')
    if (i == 30) return('LOW')
  }
  'Pending'
}

shinyApp(
  
  ################################################################################
  # UI                                                                           #
  ################################################################################
  ui = fluidPage(
    # Application title
    titlePanel('IBM PoT - Human Trafficking'),
    sidebarLayout(
      sidebarPanel(
        width = 3,
        plotlyOutput('vettingPie', height=450),
        conditionalPanel(
          condition="(typeof input.tbl_rows_selected !== 'undefined' && input.tbl_rows_selected.length > 0)", hr(),
          verbatimTextOutput('selectionDetails'),
          wellPanel(
            fluidRow(
              column(
                width=6, radioButtons(
                  'vetting', label='Vetting Level',
                  choices=c('Pending'=100, 'HIGH'=10, 'MEDIUM'=20, 'LOW'=30)
                )
              )
            )
          ),
          actionButton('saveVetting', label='Save', icon=icon('save', lib='glyphicon'))
        )
      ),
      mainPanel(
        width = 9,
        DT::dataTableOutput('tbl')
      )
    )
  ),
  
  ################################################################################
  # SERVER                                                                       #
  ################################################################################
  server = function(input, output, session) {
    # Connect to using a odbc Driver Connection string to a remote database
    conn <- idaConnect(conn.path)
    
    # Initialize the analytics package
    idaInit(conn)
    
    # Close the DB connection when the session ends
    cancel.onSessionEnded <- session$onSessionEnded(function() { idaClose(conn) })
    
    # Query to update the vetting
    updateVetting <- function(id, vetting) {
      idaQuery(
        paste0('UPDATE ', table.string, ' SET "VETTING_LEVEL" = ', vetting, ' WHERE "UUID" = \'', id, '\'')
      )
    }
    
    # Server-side observable values
    v <- reactiveValues(
      data = idaQuery(
        paste0(
          'SELECT * FROM ', table.string, ' LEFT JOIN ', table.string,
          '_ML_RESULTS USING (UUID) ORDER BY VETTING_LEVEL, NAME'
        )
      ),
      data.selected = NULL
    )
    
    # When rows are selected, update the data.selected reactive value
    observe({v$data.selected <- input$tbl_rows_selected})
    
    # When the data or the selection changes, update the radio button and the selection details
    output$selectionDetails <- reactive({
      df <- v$data
      selected <- v$data.selected
      shiny::validate(need(!is.null(df) && !is.null(selected), 'Nothing selected.'))
      updateRadioButtons(session, 'vetting', selected = df$VETTING_LEVEL[[selected]])
      paste0(
        'Name: ', df$NAME[[selected]],
        '\nGender: ', {switch(toupper(df$GENDER[[selected]]), F='Female', M='Male', 'Unknown')},
        '\nAge: ', df$AGE[[selected]],
        '\nBirth Country: ', df$BIRTH_COUNTRY[[selected]],
        '\nOccupation: ', df$OCCUPATION[[selected]],
        '\nCountries Visited: ', df$COUNTRIES_VISITED[[selected]],
        '\nCurrent Vetting: ', category.as.string(df$VETTING_LEVEL[[selected]]),
        '\nVetting Prediction: ', category.as.string(df$predCategory[[selected]])
      )
    })
    
    # When the data changes, update the vetting pie graph
    output$vettingPie <- renderPlotly({
      df <- v$data
      shiny::validate(need(is.data.frame(df) && nrow(df) > 0, 'No results.'))
      withProgress(
        message='Rendering pie graph',  {
          colors <- c(darkred, coral, darkgreen, brown2, darkgoldenrod4, darkolivegreen4, gray)
          plot_ly(
            {
              df <- rbind({
                # Vetted
                vdf <- df[df$VETTING_LEVEL != 100,]
                vdf <- as.data.frame(table(vdf$VETTING_LEVEL))
                vdf$Var1 <- revalue(
                  as.character(vdf$Var1),
                  c('10'='HIGH VETTED', '20'='MEDIUM VETTED', '30'='LOW VETTED')
                )
                vdf
              }, {
                # Predicted
                pdf <- df[df$VETTING_LEVEL == 100,]
                pdf <- as.data.frame(table(as.integer(pdf$predCategory)))
                print(pdf)
                pdf$Var1 <- revalue(
                  as.character(pdf$Var1),
                  c('10'='HIGH PREDICTED', '20'='MEDIUM PREDICTED', '30'='LOW PREDICTED', '100'='Pending')
                )
                pdf
              })
              names(df)[names(df) == 'Var1'] <- 'Vetting'
              df$Vetting <- factor(
                df$Vetting,
                c('HIGH VETTED', 'MEDIUM VETTED', 'LOW VETTED', 'HIGH PREDICTED', 'MEDIUM PREDICTED', 'LOW PREDICTED', 'Pending')
              )
              df
            }, labels=~Vetting, values=~Freq, type='pie',
            textposition='inside',
            textinfo='label+percent',
            insidetextfont=list(color='#FFFFFF'),
            hoverinfo='label+text+percent',
            source='vettingPie',
            text=~paste(Freq),
            marker=list(colors=colors, line=list(color='#FFFFFF', width=1))
          ) %>% plotly::config(displaylogo=FALSE, collaborate=FALSE) %>%
            layout(
              legend=list(orientation='h'),
              xaxis=list(showgrid=FALSE, zeroline=FALSE, showticklabels=FALSE),
              yaxis=list(showgrid=FALSE, zeroline=FALSE, showticklabels=FALSE))
        })
    })
    
    observeEvent(input$saveVetting, {
      vetting <- as.integer(isolate(input$vetting))
      id <- isolate(v$data$UUID[v$data.selected[1]])
      if (!is.na(id)) {
        withProgress(
          message='Saving vetting', detail=category.as.string(vetting), {
            v$data$VETTING_LEVEL[v$data.selected[1]] <- vetting
            updateVetting(id, vetting)
          }
        )
      }
    })
    
    output$tbl <- DT::renderDataTable(
      {
        shiny::validate(need(is.data.frame(v$data) && nrow(v$data) > 0, 'No results.'))
        v$data
      }, 
      server=TRUE,
      class='cell-border stripe',
      filter='top',
      colnames=c('ROW_ID'=1),
      extensions=c('Buttons', 'Scroller'),
      selection='single',
      options=list(
        dom='Bfrtip',
        buttons=list(
          list(extend='colvis')
        ),
        scrollX=TRUE,
        scrollY=600,
        scroller=TRUE,
        searchHighlight=TRUE,
        autoWidth=TRUE
      )
    )
  }
)

