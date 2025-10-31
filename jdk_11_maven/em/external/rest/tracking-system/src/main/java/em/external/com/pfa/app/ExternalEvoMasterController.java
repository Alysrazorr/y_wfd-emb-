package em.external.com.pfa.app;

import org.evomaster.client.java.controller.AuthUtils;
import org.evomaster.client.java.controller.ExternalSutController;
import org.evomaster.client.java.controller.InstrumentedSutStarter;
import org.evomaster.client.java.controller.api.dto.SutInfoDto;
import org.evomaster.client.java.controller.api.dto.auth.AuthenticationDto;
import org.evomaster.client.java.controller.api.dto.database.schema.DatabaseType;
import org.evomaster.client.java.controller.problem.ProblemInfo;
import org.evomaster.client.java.controller.problem.RestProblem;
import org.evomaster.client.java.sql.DbCleaner;
import org.evomaster.client.java.sql.DbSpecification;
import org.h2.tools.Server;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.List;

public class ExternalEvoMasterController extends ExternalSutController {

    public static void main(String[] args) {

        int controllerPort = 40100;
        if (args.length > 0) {
            controllerPort = Integer.parseInt(args[0]);
        }
        int sutPort = 12345;
        if (args.length > 1) {
            sutPort = Integer.parseInt(args[1]);
        }
        String jarLocation = "cs/rest/tracking-system/target";
        if (args.length > 2) {
            jarLocation = args[2];
        }
        if(! jarLocation.endsWith(".jar")) {
            jarLocation += "/tracking-system-sut.jar";
        }
        int timeoutSeconds = 120;
        if(args.length > 3){
            timeoutSeconds = Integer.parseInt(args[3]);
        }

        String command = "java";
        if(args.length > 4){
            command = args[4];
        }

        ExternalEvoMasterController controller =
                new ExternalEvoMasterController(controllerPort, jarLocation, sutPort, timeoutSeconds, command);
        InstrumentedSutStarter starter = new InstrumentedSutStarter(controller);

        starter.start();
    }


    private final int timeoutSeconds;
    private final int sutPort;
    private final int dbPort;
    private  String jarLocation;
    private Connection sqlConnection;
    private List<DbSpecification> dbSpecification;
    private Server h2;

    private String INIT_DB_SCRIPT_PATH = "/data.sql";

    public ExternalEvoMasterController() {
        this(40100, "../core/target", 12345, 120, "java");
    }

    public ExternalEvoMasterController(String jarLocation) {
        this();
        this.jarLocation = jarLocation;
    }

    public ExternalEvoMasterController(int controllerPort, String jarLocation, int sutPort, int timeoutSeconds, String command) {
        this.sutPort = sutPort;
        this.dbPort = sutPort + 1;
        this.jarLocation = jarLocation;
        this.timeoutSeconds = timeoutSeconds;
        setControllerPort(controllerPort);
        setJavaCommand(command);
    }

    private String dbUrl( ) {

        String url = "jdbc";
        url += ":h2:tcp://localhost:" + dbPort + "/mem:testdb_" + dbPort;

        return url;
    }

    @Override
    public String[] getInputParameters() {
        return new String[]{
                "--server.port=" + sutPort,
                "--spring.profiles.active=dev",
                "--spring.datasource.url=" + dbUrl() + ";DB_CLOSE_DELAY=-1",
                "--spring.datasource.username=sa",
                "--spring.datasource.password"
        };
    }

    public String[] getJVMParameters() {
        return new String[]{
        };
    }

    @Override
    public String getBaseURL() {
        return "http://localhost:" + sutPort;
    }

    @Override
    public String getPathToExecutableJar() {
        return jarLocation;
    }

    @Override
    public String getLogMessageOfInitializedServer() {
        return "Started ProjectTrackingSystemApplication in ";
    }

    @Override
    public long getMaxAwaitForInitializationInSeconds() {
        return timeoutSeconds;
    }

    @Override
    public void preStart() {

        try {
            //starting H2
            h2 = Server.createTcpServer("-tcp", "-tcpAllowOthers", "-tcpPort", "" + dbPort, "-ifNotExists");
            h2.start();
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public void postStart() {
        closeDataBaseConnection();

        try {
            Class.forName("org.h2.Driver");
            sqlConnection = DriverManager.getConnection(dbUrl(), "sa", "");

            DbCleaner.clearDatabase_H2(sqlConnection, Arrays.asList("flyway_schema_history"), null);
            dbSpecification = Arrays.asList(new DbSpecification(DatabaseType.H2,sqlConnection)
                    .withInitSqlOnResourcePath(INIT_DB_SCRIPT_PATH));

        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public void resetStateOfSUT() {
    }

    @Override
    public void preStop() {
        closeDataBaseConnection();
    }

    @Override
    public void postStop() {
        if (h2 != null) {
            h2.stop();
        }
    }

    private void closeDataBaseConnection() {
        if (sqlConnection != null) {
            try {
                sqlConnection.close();
            } catch (SQLException e) {
                e.printStackTrace();
            }
            sqlConnection = null;
        }
    }

    @Override
    public String getPackagePrefixesToCover() {
        return "com.pfa.app.";
    }


    @Override
    public ProblemInfo getProblemInfo() {

        return new RestProblem(
                "http://localhost:" + sutPort + "/app/v2/api-docs",
                null,
                null
        );
    }

    @Override
    public SutInfoDto.OutputFormat getPreferredOutputFormat() {
        return SutInfoDto.OutputFormat.JAVA_JUNIT_5;
    }

    @Override
    public List<AuthenticationDto> getInfoForAuthentication() {
        return Arrays.asList(
                AuthUtils.getForDefaultSpringFormLogin("ROLE_ADMIN", "admin", "test", "/app/login"),
                AuthUtils.getForDefaultSpringFormLogin("ROLE_EMP", "selimhorri", "test", "/app/login"),
                AuthUtils.getForDefaultSpringFormLogin("ROLE_MGR", "soumayahajjem", "test", "/app/login")
        );
    }

    @Override
    public List<DbSpecification> getDbSpecifications() {
        return dbSpecification;
    }
}
