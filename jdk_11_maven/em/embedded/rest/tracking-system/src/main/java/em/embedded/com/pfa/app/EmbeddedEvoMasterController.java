package em.embedded.com.pfa.app;


import com.pfa.app.ProjectTrackingSystemApplication;
import org.evomaster.client.java.controller.AuthUtils;
import org.evomaster.client.java.controller.EmbeddedSutController;
import org.evomaster.client.java.controller.InstrumentedSutStarter;
import org.evomaster.client.java.controller.api.dto.SutInfoDto;
import org.evomaster.client.java.controller.api.dto.auth.AuthenticationDto;
import org.evomaster.client.java.controller.api.dto.database.schema.DatabaseType;
import org.evomaster.client.java.controller.problem.ProblemInfo;
import org.evomaster.client.java.controller.problem.RestProblem;
import org.evomaster.client.java.sql.DbCleaner;
import org.evomaster.client.java.sql.DbSpecification;
import org.evomaster.client.java.sql.SqlScriptRunnerCached;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

/**
 * Class used to start/stop the SUT. This will be controller by the EvoMaster process
 */
public class EmbeddedEvoMasterController extends EmbeddedSutController {

    public static void main(String[] args) {

        int port = 40100;
        if (args.length > 0) {
            port = Integer.parseInt(args[0]);
        }

        EmbeddedEvoMasterController controller = new EmbeddedEvoMasterController(port);
        InstrumentedSutStarter starter = new InstrumentedSutStarter(controller);

        starter.start();
    }


    private ConfigurableApplicationContext ctx;
    private Connection sqlConnection;
    private List<DbSpecification> dbSpecification;

    private String INIT_DB_SCRIPT_PATH = "/data.sql";

    public EmbeddedEvoMasterController() {
        this(40100);
    }

    public EmbeddedEvoMasterController(int port) {
        setControllerPort(port);
    }

    @Override
    public String startSut() {

        ctx = SpringApplication.run(ProjectTrackingSystemApplication.class, new String[]{
                "--server.port=0",
                "--spring.datasource.url=jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1;",
                "--spring.profiles.active=dev",
                // to not execute sql file (data.sql) located in resources folder. Because flyway handles it.
                "--spring.datasource.initialization-mode=never"
        });

        if (sqlConnection != null) {
            try {
                sqlConnection.close();
            } catch (SQLException e) {
                throw new RuntimeException(e);
            }
        }
        JdbcTemplate jdbc = ctx.getBean(JdbcTemplate.class);
        try {
            sqlConnection = jdbc.getDataSource().getConnection();
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }

        DbCleaner.clearDatabase_H2(sqlConnection, Arrays.asList("flyway_schema_history"), null);
        dbSpecification = Arrays.asList(new DbSpecification(DatabaseType.H2,sqlConnection)
                .withInitSqlOnResourcePath(INIT_DB_SCRIPT_PATH));

        return "http://localhost:" + getSutPort();
    }

    protected int getSutPort() {
        return (Integer) ((Map) ctx.getEnvironment()
                .getPropertySources().get("server.ports").getSource())
                .get("local.server.port");
    }


    @Override
    public boolean isSutRunning() {
        return ctx != null && ctx.isRunning();
    }

    @Override
    public void stopSut() {
        ctx.stop();
    }

    @Override
    public String getPackagePrefixesToCover() {
        return "com.pfa.app.";
    }

    @Override
    public void resetStateOfSUT() {
    }

    @Override
    public ProblemInfo getProblemInfo() {

        return new RestProblem(
                "http://localhost:" + getSutPort() + "/app/v2/api-docs",
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
