package LANraragi::Plugin::Scripts::ETagConverter;

use strict;
use warnings;
no warnings 'uninitialized';
use utf8;
use LANraragi::Utils::Logging qw(get_plugin_logger);
use LANraragi::Utils::Database qw(redis_decode redis_encode invalidate_cache);
use LANraragi::Model::Config;
use Mojo::JSON qw(decode_json encode_json);

#Meta-information about your plugin.
sub plugin_info {

    return (
        #Standard metadata
        name        => "E-Hentai Tags Converter",
        type        => "script",
        namespace   => "etagconver",
        author      => "GrayZhao & Guerra24",
        version     => "1.0",
        description => "将原来自 E-Hentai 的英文标签转换为中文标签<br/><strong style='color:red'>警告!!! 本插件尚在测试阶段，为了您的数据安全，使用前请一定要备份数据库!</strong>",
        icon        =>
          "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAZxJREFUOE+tVNFRAjEU3HSAHWAFagW6aUCpQDsAKlA70ArUCrSCe0cFagXSgVBBnM0kmbtw58AM74fhvWTfy+6+czhyuCE8M7sCsCa5PrTfGGAIIay89wIuYWYTAPOcCCG03vtV90wENLMpgJdOQUAbAF8ptyE5S5NbNfWHajmXAQVQH+zdI9ltrgEmIYSFc+4SAEm2ulADxoKZlSc3TdPqUgasKLgB8A7gkeTDMQDPAXz+B/gqdQGom371/w7AdGjCxP9C50iK850nj7qkC2hmTwDOAMwyUE+U1KlrEZH47ZxTd4VUjoonR/yk/JKkwEsc5MMEKIB5CGHrnPsleboP4AcA+Usc9qJpGnG1cc7pjExeLFM4TJ21Bbckn8eINDMJpAVYqiEAPf2NpPIxypPNTMreA7jIfA1MFz2ZNkiTZt5PeiqnCTOglFP3XlRi1OUiTnfCvH5tCEHEi6dtR90oRs2ZOO2K01PZzDTZddU+kp7F8N5rj0skT5ZGO7ZJX5TMjXiKW5A4bvNHICMmKiRKrA36cEzlffJHB/wDWGrwFa3VL0wAAAAASUVORK5CYII=",
        parameters => [
            {
                type => "string",
                desc => "EhTagTranslation项目的JSON数据库文件(db.text.json)的绝对路径"
            },
        ]
    );

}

# Mandatory function to be implemented by your script
sub run_script {
    shift;
    my $lrr_info = shift;     # Global info hash
    my ($db_path) = @_;       # Plugin parameters

    my $logger = get_plugin_logger();
    my $redis  = LANraragi::Model::Config->get_redis;

    my @keys = $redis->keys('????????????????????????????????????????'); #40-character long keys only => Archive IDs

    # 计数
    my $count = 0;

    # 打开本地JSON数据库
    my $json_text = do {
        open( my $json_fh, "<", $db_path )
          or $logger->debug("Can't open $db_path: $!\n");
        local $/;
        <$json_fh>;
    };
    my $json   = decode_json($json_text);
    my $target = $json->{'data'};

    #Parse the archive list and add them to JSON.
    foreach my $id (@keys) {

        my %hash = $redis->hgetall($id);
        my ($tags) = redis_decode(@hash{qw(tags)});

        # 替换原有 category 为 reclass
        $tags =~ s/category/reclass/g;
        # 将字符串转为数组，并且去除字符串前后空格
        my @list = map { s/^\s+|\s+$//g; $_ } split( /,/, $tags );

        for my $item (@list) {
            my ( $namespace, $word ) = split( /:/, $item );
            for my $element (@$target) {

                # 如果$namespace与'namespace'字段相同，则进行替换
                if ( $element->{'namespace'} eq $namespace ) {
                    my $name = $element->{'frontMatters'}->{'name'};
                    $item =~ s/$namespace/$name/;
                    my $data = $element->{'data'};

                    # 如果在'data'字段中存在$key，则进行替换
                    if ( exists $data->{$word} ) {
                        my $value = $data->{$word}->{'name'};
                        $item =~ s/$word/$value/;
                    }
                    last;
                }
            }
        }

        $count++;
        # 将数组重新拼接为字符串
        my $ehtags = join( ', ', @list );
        $logger->info("Sending the following tags to LRR: $ehtags");

        $redis->hset( $id, "tags", redis_encode($ehtags) );
    }

    invalidate_cache();
    $redis->quit();

    return ( modified => $count, message => "标签转换已完成..." );
}

1;
