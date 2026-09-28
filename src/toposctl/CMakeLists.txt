add_executable(toposctl main.cpp)
target_link_libraries(toposctl PRIVATE Qt::Core Qt::DBus)
install(TARGETS toposctl ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
